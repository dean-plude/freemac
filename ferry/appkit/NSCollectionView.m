/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: collection views, their items and their layouts. Our own
 * code, written from Apple's public API documentation.
 *
 * A collection view works one of two ways. With a data source it is the
 * modern kind: the data source gives the number of sections and of items
 * in each, and makes each item (usually with makeItemWithIdentifier:
 * forIndexPath:, from a registered class or nib) as it comes into sight; a
 * layout object (flow or grid, or the app's own subclass) says where each
 * goes. Items that leave the visible part are kept for reuse. Without a
 * data source it is the older kind: an array of content objects, and an
 * item made for each of them by copying the item prototype (see
 * ANibCopyItemPrototype in NSNib.m), laid out in a grid from the
 * prototype's size, the minimum and maximum item sizes and the maximum
 * numbers of rows and columns.
 *
 * The view is flipped, and inside a scroll view it is as big as its layout's
 * content or the clip view, whichever is bigger. Laying out happens when it
 * is needed: before drawing, hit testing and the queries that need it, and
 * on the next turn of the run loop after a change.
 *
 * Selection changed from code calls no delegate method. A click or a key
 * asks the delegate (should select, should deselect, and the highlight
 * states) and tells it afterwards, as the documentation describes; a Mac
 * highlights while the mouse is down and selects on its release, and so
 * does Ferry, from the view's own mouse down and mouse up. Changes to items
 * and sections, alone or in performBatchUpdates:completionHandler:, take
 * effect at once with no animation: the selection and the items in sight
 * move with the items they belong to, and the completion handler is called
 * with YES straight away.
 *
 * In a nib, the keys of the collection view's own settings aren't in
 * Apple's documentation. Ferry reads NSSelectable, NSAllowsMultipleSelection,
 * NSAllowsEmptySelection, NSBackgroundColors, NSMaxNumberOfGridRows,
 * NSMaxNumberOfGridColumns, NSMinGridSize, NSMaxGridSize and
 * NSCollectionViewLayout when they are there; the item prototype, data
 * source and delegate are outlets. */
#import "AInternal.h"

NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionHeader =
    @"NSCollectionElementKindSectionHeader";
NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionFooter =
    @"NSCollectionElementKindSectionFooter";
NSCollectionViewSupplementaryElementKind const NSCollectionElementKindInterItemGapIndicator =
    @"NSCollectionElementKindInterItemGapIndicator";
NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionCollapseButton =
    @"NSCollectionElementKindSectionCollapseButton";

/* In NSNib.m: a new copy of an item prototype that came from a nib (+1). */
id ANibCopyItemPrototype(id item);

static NSIndexPath *IP(NSInteger section, NSInteger item) { return [NSIndexPath indexPathForItem:item inSection:section]; }

@interface NSCollectionView (FerryLayout)
- (NSSize)_layoutSize;
- (NSRect)_visibleArea;
- (void)_layoutInvalidated;
- (NSSize)_defaultItemSize;
@end

@interface NSCollectionViewLayout (FerryPrivate)
- (void)_setCollectionView:(NSCollectionView *)cv;
- (void)_prepareIfNeeded;
- (BOOL)_isValid;
@end

/* ---- items ------------------------------------------------------------------------------ */

@implementation NSCollectionViewItem {
    NSCollectionView *_cv;   /* not retained */
    BOOL _selected;
    NSCollectionViewItemHighlightState _highlight;
    NSImageView *_imageView; /* not retained, as outlets */
    NSTextField *_textField;
    NSString *_identifier;
}
- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}
- (NSCollectionView *)collectionView { return _cv; }
- (void)_setCollectionView:(NSCollectionView *)cv { _cv = cv; }
- (BOOL)isSelected { return _selected; }
- (void)setSelected:(BOOL)selected { _selected = selected; }
- (NSCollectionViewItemHighlightState)highlightState { return _highlight; }
- (void)setHighlightState:(NSCollectionViewItemHighlightState)state { _highlight = state; }
- (NSImageView *)imageView { return _imageView; }
- (void)setImageView:(NSImageView *)v { _imageView = v; }
- (NSTextField *)textField { return _textField; }
- (void)setTextField:(NSTextField *)f { _textField = f; }
- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)identifier
{
    if (identifier == _identifier)
        return;
    id wasIdentifier = _identifier;
    _identifier = [identifier copy];
    [wasIdentifier release];
}
- (NSArray *)draggingImageComponents { return [NSArray array]; }
- (void)prepareForReuse {}
- (void)applyLayoutAttributes:(NSCollectionViewLayoutAttributes *)attributes {}

/* A copy, as an item prototype is copied for each content object: decoded
 * again from its nib when it came from one; otherwise a new item of its
 * class, which loads its own nib if it has one, and failing that a new
 * view of the prototype's view's class and size. */
- (id)copyWithZone:(NSZone *)zone
{
    NSCollectionViewItem *c = ANibCopyItemPrototype(self);
    if (c) {
        [c setIdentifier:_identifier];
        return c;
    }
    c = [[[self class] alloc] initWithNibName:[self nibName] bundle:[self nibBundle]];
    BOOL ownView = [[self class] instanceMethodForSelector:@selector(loadView)] !=
                   [NSCollectionViewItem instanceMethodForSelector:@selector(loadView)];
    if (![self nibName] && !ownView) {
        NSView *v = [self viewIfLoaded];
        if (v) {
            AWarnOnce("copying the subviews of an item prototype's view made in code");
            NSView *nv = [[[v class] alloc] initWithFrame:[v frame]];
            [c setView:nv];
            [nv release];
        }
    }
    [c setIdentifier:_identifier];
    return c;
}
@end

/* ---- layout attributes, update items, invalidation contexts ------------------------------ */

@implementation NSCollectionViewLayoutAttributes {
    NSRect _frame;
    CGFloat _alpha;
    NSInteger _z;
    BOOL _hidden;
    NSIndexPath *_path;
    NSCollectionElementCategory _category;
    NSString *_kind;
}
- (instancetype)init
{
    if ((self = [super init]))
        _alpha = 1;
    return self;
}
+ (instancetype)_attributesWithPath:(NSIndexPath *)path category:(NSCollectionElementCategory)cat kind:(NSString *)kind
{
    NSCollectionViewLayoutAttributes *a = [[[self alloc] init] autorelease];
    a->_path = [path retain];
    a->_category = cat;
    a->_kind = [kind copy];
    return a;
}
+ (instancetype)layoutAttributesForItemWithIndexPath:(NSIndexPath *)indexPath
{
    return [self _attributesWithPath:indexPath category:NSCollectionElementCategoryItem kind:nil];
}
+ (instancetype)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)indexPath
{
    return [self _attributesWithPath:indexPath category:NSCollectionElementCategoryInterItemGap
                                kind:NSCollectionElementKindInterItemGapIndicator];
}
+ (instancetype)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind withIndexPath:(NSIndexPath *)indexPath
{
    return [self _attributesWithPath:indexPath category:NSCollectionElementCategorySupplementaryView kind:kind];
}
+ (instancetype)layoutAttributesForDecorationViewOfKind:(NSString *)kind withIndexPath:(NSIndexPath *)indexPath
{
    return [self _attributesWithPath:indexPath category:NSCollectionElementCategoryDecorationView kind:kind];
}
- (void)dealloc
{
    [_path release];
    [_kind release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSCollectionViewLayoutAttributes *c = [[[self class] alloc] init];
    c->_frame = _frame;
    c->_alpha = _alpha;
    c->_z = _z;
    c->_hidden = _hidden;
    c->_path = [_path retain];
    c->_category = _category;
    c->_kind = [_kind copy];
    return c;
}
- (NSRect)frame { return _frame; }
- (void)setFrame:(NSRect)f { _frame = f; }
- (NSSize)size { return _frame.size; }
- (void)setSize:(NSSize)s { _frame.size = s; }
- (CGFloat)alpha { return _alpha; }
- (void)setAlpha:(CGFloat)a { _alpha = a; }
- (NSInteger)zIndex { return _z; }
- (void)setZIndex:(NSInteger)z { _z = z; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (NSIndexPath *)indexPath { return _path; }
- (void)setIndexPath:(NSIndexPath *)p
{
    [p retain];
    [_path release];
    _path = p;
}
- (NSCollectionElementCategory)representedElementCategory { return _category; }
- (NSString *)representedElementKind { return _kind; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s %ld-%ld %@ frame %@>", object_getClassName(self),
                                      (long)[_path section], (long)[_path item], _kind ?: @"item",
                                      NSStringFromRect(_frame)];
}
@end

@implementation NSCollectionViewUpdateItem {
@public
    NSIndexPath *_before, *_after;
    NSCollectionUpdateAction _action;
}
- (void)dealloc
{
    [_before release];
    [_after release];
    [super dealloc];
}
- (NSIndexPath *)indexPathBeforeUpdate { return _before; }
- (NSIndexPath *)indexPathAfterUpdate { return _after; }
- (NSCollectionUpdateAction)updateAction { return _action; }
@end

@implementation NSCollectionViewLayoutInvalidationContext {
@public
    BOOL _everything, _counts;
    NSPoint _offsetAdjust;
    NSSize _sizeAdjust;
    NSMutableSet *_items;
}
- (instancetype)init
{
    if ((self = [super init]))
        _everything = YES;
    return self;
}
- (void)dealloc
{
    [_items release];
    [super dealloc];
}
- (BOOL)invalidateEverything { return _everything; }
- (BOOL)invalidateDataSourceCounts { return _counts || _everything; }
- (NSPoint)contentOffsetAdjustment { return _offsetAdjust; }
- (void)setContentOffsetAdjustment:(NSPoint)p { _offsetAdjust = p; }
- (NSSize)contentSizeAdjustment { return _sizeAdjust; }
- (void)setContentSizeAdjustment:(NSSize)s { _sizeAdjust = s; }
- (void)invalidateItemsAtIndexPaths:(NSSet *)paths
{
    if (!_items)
        _items = [[NSMutableSet alloc] init];
    [_items unionSet:paths];
    _everything = NO;
}
- (NSSet *)invalidatedItemIndexPaths { return _items; }
@end

/* ---- the layout base class ---------------------------------------------------------------- */

@implementation NSCollectionViewLayout {
    NSCollectionView *_cv;   /* not retained: the collection view keeps its layout */
    NSMutableDictionary *_decorations;
    BOOL _valid, _preparing;
}
+ (Class)layoutAttributesClass { return [NSCollectionViewLayoutAttributes class]; }
+ (Class)invalidationContextClass { return [NSCollectionViewLayoutInvalidationContext class]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    [_decorations release];
    [super dealloc];
}
- (NSCollectionView *)collectionView { return _cv; }
- (void)_setCollectionView:(NSCollectionView *)cv
{
    _cv = cv;
    _valid = NO;
}
- (BOOL)_isValid { return _valid; }
- (void)_prepareIfNeeded
{
    if (_valid || _preparing || !_cv)
        return;
    _preparing = YES;
    @try {
        [self prepareLayout];
    } @finally {
        _preparing = NO;
    }
    _valid = YES;
}
- (void)invalidateLayout
{
    [self invalidateLayoutWithContext:[[[[[self class] invalidationContextClass] alloc] init] autorelease]];
}
- (void)invalidateLayoutWithContext:(NSCollectionViewLayoutInvalidationContext *)context
{
    _valid = NO;
    [_cv _layoutInvalidated];
}
- (void)registerClass:(Class)viewClass forDecorationViewOfKind:(NSString *)kind
{
    if (!_decorations)
        _decorations = [[NSMutableDictionary alloc] init];
    if (viewClass && kind)
        [_decorations setObject:viewClass forKey:kind];
    else if (kind)
        [_decorations removeObjectForKey:kind];
}
- (void)registerNib:(NSNib *)nib forDecorationViewOfKind:(NSString *)kind
{
    if (!_decorations)
        _decorations = [[NSMutableDictionary alloc] init];
    if (nib && kind)
        [_decorations setObject:nib forKey:kind];
    else if (kind)
        [_decorations removeObjectForKey:kind];
}
- (void)prepareLayout {}
- (NSSize)collectionViewContentSize { return NSZeroSize; }
- (NSArray *)layoutAttributesForElementsInRect:(NSRect)rect { return [NSArray array]; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath { return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind
                                                                     atIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)kind
                                                                  atIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDropTargetAtPoint:(NSPoint)point { return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds { return NO; }
- (NSPoint)targetContentOffsetForProposedContentOffset:(NSPoint)proposed { return proposed; }
- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems {}
- (void)finalizeCollectionViewUpdates {}
@end

/* ---- the flow layout ---------------------------------------------------------------------- */

/* One section of a flow layout: its items' and its header's and footer's
 * attributes, and where it starts and ends along the scrolling direction. */
@interface AFlowSection : NSObject {
@public
    NSMutableArray *items;
    NSCollectionViewLayoutAttributes *header, *footer;
    CGFloat start, end;
}
@end
@implementation AFlowSection
- (instancetype)init
{
    if ((self = [super init]))
        items = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [items release];
    [header release];
    [footer release];
    [super dealloc];
}
@end

@implementation NSCollectionViewFlowLayout {
    CGFloat _lineSpacing, _interSpacing;
    NSSize _itemSize, _estimated, _headerSize, _footerSize;
    NSCollectionViewScrollDirection _direction;
    NSEdgeInsets _inset;
    BOOL _pinHeaders, _pinFooters;
    NSMutableIndexSet *_collapsed;
    NSMutableArray *_sections;
    NSSize _content;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _lineSpacing = 10;
        _interSpacing = 10;
        _itemSize = NSMakeSize(50, 50);
        _collapsed = [[NSMutableIndexSet alloc] init];
        _sections = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_collapsed release];
    [_sections release];
    [super dealloc];
}

#define FLOW_PROP(type, get, set, ivar)                                                                    \
    -(type)get { return ivar; }                                                                            \
    -(void)set:(type)v                                                                                     \
    {                                                                                                      \
        ivar = v;                                                                                          \
        [self invalidateLayout];                                                                           \
    }
FLOW_PROP(CGFloat, minimumLineSpacing, setMinimumLineSpacing, _lineSpacing)
FLOW_PROP(CGFloat, minimumInteritemSpacing, setMinimumInteritemSpacing, _interSpacing)
FLOW_PROP(NSSize, itemSize, setItemSize, _itemSize)
FLOW_PROP(NSSize, estimatedItemSize, setEstimatedItemSize, _estimated)
FLOW_PROP(NSCollectionViewScrollDirection, scrollDirection, setScrollDirection, _direction)
FLOW_PROP(NSSize, headerReferenceSize, setHeaderReferenceSize, _headerSize)
FLOW_PROP(NSSize, footerReferenceSize, setFooterReferenceSize, _footerSize)
FLOW_PROP(NSEdgeInsets, sectionInset, setSectionInset, _inset)
FLOW_PROP(BOOL, sectionHeadersPinToVisibleBounds, setSectionHeadersPinToVisibleBounds, _pinHeaders)
FLOW_PROP(BOOL, sectionFootersPinToVisibleBounds, setSectionFootersPinToVisibleBounds, _pinFooters)

- (BOOL)sectionAtIndexIsCollapsed:(NSUInteger)section { return [_collapsed containsIndex:section]; }
- (void)collapseSectionAtIndex:(NSUInteger)section
{
    [_collapsed addIndex:section];
    [self invalidateLayout];
}
- (void)expandSectionAtIndex:(NSUInteger)section
{
    [_collapsed removeIndex:section];
    [self invalidateLayout];
}

/* Positions are worked out along the lines (u) and across them, in the
 * scrolling direction (v), then turned into x and y. */
static NSRect flow_rect(BOOL horizontal, CGFloat u, CGFloat v, CGFloat du, CGFloat dv)
{
    return horizontal ? NSMakeRect(v, u, dv, du) : NSMakeRect(u, v, du, dv);
}

- (void)prepareLayout
{
    [_sections removeAllObjects];
    NSCollectionView *cv = [self collectionView];
    id d = [cv delegate];
    BOOL horizontal = _direction == NSCollectionViewScrollDirectionHorizontal;
    NSSize area = [cv _layoutSize];
    CGFloat W = horizontal ? area.height : area.width;
    Class attrs = [[self class] layoutAttributesClass];
    CGFloat v = 0;
    NSInteger sections = [cv numberOfSections];
    for (NSInteger s = 0; s < sections; s++) {
        AFlowSection *sec = [[AFlowSection alloc] init];
        [_sections addObject:sec];
        [sec release];
        sec->start = v;
        NSEdgeInsets in = _inset;
        if ([d respondsToSelector:@selector(collectionView:layout:insetForSectionAtIndex:)])
            in = [(id)d collectionView:cv layout:self insetForSectionAtIndex:s];
        CGFloat lineSpacing = _lineSpacing, inter = _interSpacing;
        if ([d respondsToSelector:@selector(collectionView:layout:minimumLineSpacingForSectionAtIndex:)])
            lineSpacing = [(id)d collectionView:cv layout:self minimumLineSpacingForSectionAtIndex:s];
        if ([d respondsToSelector:@selector(collectionView:layout:minimumInteritemSpacingForSectionAtIndex:)])
            inter = [(id)d collectionView:cv layout:self minimumInteritemSpacingForSectionAtIndex:s];
        CGFloat ub = horizontal ? in.top : in.left, ua = horizontal ? in.bottom : in.right;
        CGFloat vb = horizontal ? in.left : in.top, va = horizontal ? in.right : in.bottom;

        NSSize hs = _headerSize;
        if ([d respondsToSelector:@selector(collectionView:layout:referenceSizeForHeaderInSection:)])
            hs = [(id)d collectionView:cv layout:self referenceSizeForHeaderInSection:s];
        CGFloat hv = horizontal ? hs.width : hs.height;
        if (hv > 0) {
            sec->header = [[attrs layoutAttributesForSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                                                               withIndexPath:IP(s, 0)] retain];
            [sec->header setFrame:flow_rect(horizontal, 0, v, W, hv)];
            v += hv;
        }
        v += vb;

        NSInteger n = [cv numberOfItemsInSection:s];
        BOOL collapsed = [_collapsed containsIndex:(NSUInteger)s];
        CGFloat avail = W - ub - ua;
        NSInteger i = 0;
        BOOL anyLine = NO;
        while (i < n) {
            /* one line: as many items as fit (at least one) */
            NSMutableArray *line = [NSMutableArray array];
            CGFloat used = 0, thick = 0;
            NSInteger j = i;
            for (; j < n; j++) {
                NSIndexPath *p = IP(s, j);
                NSSize sz = _itemSize;
                if ([d respondsToSelector:@selector(collectionView:layout:sizeForItemAtIndexPath:)])
                    sz = [(id)d collectionView:cv layout:self sizeForItemAtIndexPath:p];
                CGFloat du = horizontal ? sz.height : sz.width, dv = horizontal ? sz.width : sz.height;
                CGFloat need = [line count] ? used + inter + du : du;
                if ([line count] && need > avail + 0.001 && !collapsed)
                    break;
                NSCollectionViewLayoutAttributes *a = [attrs layoutAttributesForItemWithIndexPath:p];
                [a setFrame:flow_rect(horizontal, 0, 0, du, dv)];
                if (collapsed && [line count] && need > avail + 0.001)
                    [a setHidden:YES];  /* a collapsed section shows one line */
                [line addObject:a];
                if (![a isHidden]) {
                    used = need;
                    thick = fmax(thick, dv);
                }
            }
            BOOL last = j >= n;
            NSUInteger shown = 0;
            for (NSCollectionViewLayoutAttributes *a in line)
                if (![a isHidden])
                    shown++;
            /* full lines are spread over the width; the last starts at the start */
            CGFloat gap = inter;
            if (!last && shown > 1)
                gap = inter + (avail - used) / (CGFloat)(shown - 1);
            if (anyLine)
                v += lineSpacing;
            CGFloat u = ub;
            for (NSCollectionViewLayoutAttributes *a in line) {
                NSRect f = [a frame];
                CGFloat du = horizontal ? f.size.height : f.size.width, dv = horizontal ? f.size.width : f.size.height;
                if ([a isHidden]) {
                    [a setFrame:flow_rect(horizontal, u, v, du, dv)];
                } else {
                    [a setFrame:flow_rect(horizontal, u, v + (thick - dv) / 2, du, dv)];
                    u += du + gap;
                }
                [sec->items addObject:a];
            }
            v += thick;
            anyLine = YES;
            i = j;
        }
        v += va;

        NSSize fs = _footerSize;
        if ([d respondsToSelector:@selector(collectionView:layout:referenceSizeForFooterInSection:)])
            fs = [(id)d collectionView:cv layout:self referenceSizeForFooterInSection:s];
        CGFloat fv = horizontal ? fs.width : fs.height;
        if (fv > 0) {
            sec->footer = [[attrs layoutAttributesForSupplementaryViewOfKind:NSCollectionElementKindSectionFooter
                                                               withIndexPath:IP(s, 0)] retain];
            [sec->footer setFrame:flow_rect(horizontal, 0, v, W, fv)];
            v += fv;
        }
        sec->end = v;
    }
    _content = horizontal ? NSMakeSize(v, W) : NSMakeSize(W, v);
}

- (NSSize)collectionViewContentSize
{
    [self _prepareIfNeeded];
    return _content;
}

/* A header or footer kept in sight while its section is. */
- (NSCollectionViewLayoutAttributes *)_pinned:(NSCollectionViewLayoutAttributes *)a section:(AFlowSection *)sec
                                       header:(BOOL)header
{
    if (!a || !(header ? _pinHeaders : _pinFooters))
        return a;
    BOOL horizontal = _direction == NSCollectionViewScrollDirectionHorizontal;
    NSRect vis = [[self collectionView] _visibleArea];
    NSRect f = [a frame];
    CGFloat pos = horizontal ? f.origin.x : f.origin.y, len = horizontal ? f.size.width : f.size.height;
    CGFloat lo = horizontal ? NSMinX(vis) : NSMinY(vis), hi = horizontal ? NSMaxX(vis) : NSMaxY(vis);
    CGFloat np = pos;
    if (header) {
        CGFloat limit = (sec->footer ? (horizontal ? NSMinX([sec->footer frame]) : NSMinY([sec->footer frame]))
                                     : sec->end) - len;
        np = fmax(pos, fmin(lo, limit));
    } else {
        CGFloat limit = sec->header ? (horizontal ? NSMaxX([sec->header frame]) : NSMaxY([sec->header frame]))
                                    : sec->start;
        np = fmin(pos, fmax(hi - len, limit));
    }
    if (np == pos)
        return a;
    NSCollectionViewLayoutAttributes *c = [[a copy] autorelease];
    if (horizontal)
        f.origin.x = np;
    else
        f.origin.y = np;
    [c setFrame:f];
    [c setZIndex:1];
    return c;
}

- (NSArray *)layoutAttributesForElementsInRect:(NSRect)rect
{
    [self _prepareIfNeeded];
    NSMutableArray *out = [NSMutableArray array];
    for (AFlowSection *sec in _sections) {
        for (NSCollectionViewLayoutAttributes *a in sec->items)
            if (![a isHidden] && NSIntersectsRect([a frame], rect))
                [out addObject:a];
        NSCollectionViewLayoutAttributes *h = [self _pinned:sec->header section:sec header:YES];
        NSCollectionViewLayoutAttributes *f = [self _pinned:sec->footer section:sec header:NO];
        if (h && NSIntersectsRect([h frame], rect))
            [out addObject:h];
        if (f && NSIntersectsRect([f frame], rect))
            [out addObject:f];
    }
    return out;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p
{
    [self _prepareIfNeeded];
    if ([p length] < 2 || [p section] < 0 || [p section] >= (NSInteger)[_sections count])
        return nil;
    AFlowSection *sec = [_sections objectAtIndex:(NSUInteger)[p section]];
    if ([p item] < 0 || [p item] >= (NSInteger)[sec->items count])
        return nil;
    return [sec->items objectAtIndex:(NSUInteger)[p item]];
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind
                                                                     atIndexPath:(NSIndexPath *)p
{
    [self _prepareIfNeeded];
    if ([p section] < 0 || [p section] >= (NSInteger)[_sections count])
        return nil;
    AFlowSection *sec = [_sections objectAtIndex:(NSUInteger)[p section]];
    if ([kind isEqualToString:NSCollectionElementKindSectionHeader])
        return [self _pinned:sec->header section:sec header:YES];
    if ([kind isEqualToString:NSCollectionElementKindSectionFooter])
        return [self _pinned:sec->footer section:sec header:NO];
    return nil;
}
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds
{
    BOOL horizontal = _direction == NSCollectionViewScrollDirectionHorizontal;
    return horizontal ? newBounds.size.height != _content.height : newBounds.size.width != _content.width;
}
@end

/* ---- the grid layout ---------------------------------------------------------------------- */

@implementation NSCollectionViewGridLayout {
    NSEdgeInsets _margins;
    CGFloat _inter, _line;
    NSUInteger _maxRows, _maxCols;
    NSSize _min, _max;
    NSArray *_colors;
    NSMutableArray *_frames;   /* one array of attributes for each section */
    NSSize _content;
    CGFloat _rowPitch;
}
- (instancetype)init
{
    if ((self = [super init]))
        _frames = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [_colors release];
    [_frames release];
    [super dealloc];
}
#define GRID_PROP(type, get, set, ivar)                                                                    \
    -(type)get { return ivar; }                                                                            \
    -(void)set:(type)v                                                                                     \
    {                                                                                                      \
        ivar = v;                                                                                          \
        [self invalidateLayout];                                                                           \
    }
GRID_PROP(NSEdgeInsets, margins, setMargins, _margins)
GRID_PROP(CGFloat, minimumInteritemSpacing, setMinimumInteritemSpacing, _inter)
GRID_PROP(CGFloat, minimumLineSpacing, setMinimumLineSpacing, _line)
GRID_PROP(NSUInteger, maximumNumberOfRows, setMaximumNumberOfRows, _maxRows)
GRID_PROP(NSUInteger, maximumNumberOfColumns, setMaximumNumberOfColumns, _maxCols)
GRID_PROP(NSSize, minimumItemSize, setMinimumItemSize, _min)
GRID_PROP(NSSize, maximumItemSize, setMaximumItemSize, _max)
- (NSArray *)backgroundColors { return _colors; }
- (void)setBackgroundColors:(NSArray *)colors
{
    if (colors == _colors)
        return;
    id wasColors = _colors;
    _colors = [colors copy];
    [wasColors release];
    [[self collectionView] setNeedsDisplay:YES];
}

/* The grid for n items in a width: columns from the minimum item size,
 * each item stretched to share the width (up to the maximum item size);
 * with a row limit and no column limit, the items run in that many rows,
 * across. */
- (void)_grid:(NSUInteger)n width:(CGFloat)W cols:(NSUInteger *)colsOut rows:(NSUInteger *)rowsOut
         size:(NSSize *)sizeOut
{
    NSSize min = _min;
    if (min.width <= 0 || min.height <= 0) {
        NSSize d = [[self collectionView] _defaultItemSize];
        if (min.width <= 0)
            min.width = d.width;
        if (min.height <= 0)
            min.height = d.height;
    }
    CGFloat avail = W - _margins.left - _margins.right;
    NSUInteger cols, rows;
    NSSize size = min;
    if (_maxRows && !_maxCols) {
        rows = MIN(_maxRows, MAX(n, (NSUInteger)1));
        cols = MAX((n + rows - 1) / rows, (NSUInteger)1);
    } else {
        cols = (NSUInteger)fmax(1, floor((avail + _inter) / (min.width + _inter)));
        if (_maxCols)
            cols = MIN(cols, _maxCols);
        rows = (n + cols - 1) / cols;
        if (_maxRows)
            rows = MIN(rows, _maxRows);
        CGFloat w = (avail - _inter * (CGFloat)(cols - 1)) / (CGFloat)cols;
        if (_max.width > 0)
            w = fmin(w, _max.width);
        size.width = fmax(min.width, floor(w));
    }
    *colsOut = cols;
    *rowsOut = rows;
    *sizeOut = size;
}
- (NSRect)_frameAtIndex:(NSUInteger)i count:(NSUInteger)n
{
    NSUInteger cols, rows;
    NSSize size;
    [self _grid:n width:[[self collectionView] _layoutSize].width cols:&cols rows:&rows size:&size];
    NSUInteger r, c;
    if (_maxRows && !_maxCols) {
        c = i / rows;
        r = i % rows;
    } else {
        r = i / cols;
        c = i % cols;
    }
    return NSMakeRect(_margins.left + (CGFloat)c * (size.width + _inter),
                      _margins.top + (CGFloat)r * (size.height + _line), size.width, size.height);
}

- (void)prepareLayout
{
    [_frames removeAllObjects];
    NSCollectionView *cv = [self collectionView];
    NSInteger sections = [cv numberOfSections];
    NSUInteger total = 0;
    for (NSInteger s = 0; s < sections; s++)
        total += (NSUInteger)MAX([cv numberOfItemsInSection:s], 0);
    NSUInteger cols, rows;
    NSSize size;
    CGFloat W = [cv _layoutSize].width;
    [self _grid:total width:W cols:&cols rows:&rows size:&size];
    Class attrs = [[self class] layoutAttributesClass];
    NSUInteger flat = 0, shown = MIN(total, cols * rows);
    for (NSInteger s = 0; s < sections; s++) {
        NSMutableArray *sec = [NSMutableArray array];
        NSInteger n = [cv numberOfItemsInSection:s];
        for (NSInteger i = 0; i < n; i++, flat++) {
            NSCollectionViewLayoutAttributes *a = [attrs layoutAttributesForItemWithIndexPath:IP(s, i)];
            [a setFrame:[self _frameAtIndex:flat count:total]];
            if (flat >= shown)
                [a setHidden:YES];  /* past the last row allowed */
            [sec addObject:a];
        }
        [_frames addObject:sec];
    }
    _rowPitch = size.height + _line;
    CGFloat width = _margins.left + _margins.right + (CGFloat)cols * size.width + (CGFloat)(cols ? cols - 1 : 0) * _inter;
    CGFloat height = _margins.top + _margins.bottom + (CGFloat)rows * size.height +
                     (CGFloat)(rows ? rows - 1 : 0) * _line;
    _content = NSMakeSize(fmax(W, width), height);
}
- (CGFloat)_rowPitch
{
    [self _prepareIfNeeded];
    return _rowPitch;
}
- (CGFloat)_firstRow { return _margins.top; }
- (NSSize)collectionViewContentSize
{
    [self _prepareIfNeeded];
    return _content;
}
- (NSArray *)layoutAttributesForElementsInRect:(NSRect)rect
{
    [self _prepareIfNeeded];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *sec in _frames)
        for (NSCollectionViewLayoutAttributes *a in sec)
            if (![a isHidden] && NSIntersectsRect([a frame], rect))
                [out addObject:a];
    return out;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p
{
    [self _prepareIfNeeded];
    if ([p section] < 0 || [p section] >= (NSInteger)[_frames count])
        return nil;
    NSArray *sec = [_frames objectAtIndex:(NSUInteger)[p section]];
    if ([p item] < 0 || [p item] >= (NSInteger)[sec count])
        return nil;
    return [sec objectAtIndex:(NSUInteger)[p item]];
}
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds { return YES; }
@end

/* ---- one place in a batch of updates ------------------------------------------------------ */

/* What is at one item's place while updates are applied: whether it is
 * selected and the item showing it, which move with it. */
@interface ASlot : NSObject {
@public
    BOOL selected, removed;
    NSCollectionViewItem *item;
    NSIndexPath *was;
}
@end
@implementation ASlot
- (void)dealloc
{
    [item release];
    [was release];
    [super dealloc];
}
@end

/* One change asked for, applied when the batch it is in ends. */
@interface AUpdate : NSObject {
@public
    NSCollectionUpdateAction action;
    BOOL sections;
    NSArray *paths;          /* items: index paths; sections: NSNumbers */
    NSIndexPath *from, *to;  /* a move */
}
@end
@implementation AUpdate
- (void)dealloc
{
    [paths release];
    [from release];
    [to release];
    [super dealloc];
}
@end

/* ---- the collection view ------------------------------------------------------------------ */

@implementation NSCollectionView {
    id _dataSource, _delegate;    /* not retained */
    NSCollectionViewLayout *_layout;
    NSCollectionViewGridLayout *_legacyLayout;
    NSView *_backgroundView;
    BOOL _bgScrolls;
    NSArray *_bgColors;
    BOOL _selectable, _allowsEmpty, _allowsMultiple;
    NSMutableSet *_selection;
    NSMutableDictionary *_itemClasses, *_itemNibs, *_suppClasses, *_suppNibs;
    NSMutableDictionary *_reuseItems, *_reuseViews;
    NSMutableDictionary *_visible;            /* index path -> item */
    NSMutableDictionary *_visibleSupp;        /* kind -> (index path -> view) */
    NSMutableArray *_counts;                  /* items in each section */
    BOOL _countsValid, _needsTile, _tileScheduled, _tiling;
    NSInteger _batch;
    NSMutableArray *_pending;                 /* AUpdates of the batch in progress */
    /* the older way */
    NSArray *_content;
    NSCollectionViewItem *_prototype;
    NSMutableArray *_legacyItems;
    NSUInteger _maxRows, _maxCols;
    NSSize _minItem, _maxItem;
    /* clicks */
    NSIndexPath *_anchor, *_lead;
    NSSet *_pressSelect, *_pressDeselect;
    BOOL _pressed;
    NSView *_observedClip;
}

+ (void)initialize
{
    if (self == [NSCollectionView class]) {
        [self exposeBinding:NSContentBinding];
        [self exposeBinding:NSSelectionIndexesBinding];
    }
}

- (void)_setUpCollection
{
    _selectable = NO;
    _allowsEmpty = YES;
    _selection = [[NSMutableSet alloc] init];
    _itemClasses = [[NSMutableDictionary alloc] init];
    _itemNibs = [[NSMutableDictionary alloc] init];
    _suppClasses = [[NSMutableDictionary alloc] init];
    _suppNibs = [[NSMutableDictionary alloc] init];
    _reuseItems = [[NSMutableDictionary alloc] init];
    _reuseViews = [[NSMutableDictionary alloc] init];
    _visible = [[NSMutableDictionary alloc] init];
    _visibleSupp = [[NSMutableDictionary alloc] init];
    _counts = [[NSMutableArray alloc] init];
    _legacyItems = [[NSMutableArray alloc] init];
    _legacyLayout = [[NSCollectionViewGridLayout alloc] init];
    [_legacyLayout _setCollectionView:self];
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUpCollection];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setUpCollection];
    if ([coder containsValueForKey:@"NSSelectable"])
        _selectable = [coder decodeBoolForKey:@"NSSelectable"];
    if ([coder containsValueForKey:@"NSAllowsMultipleSelection"])
        _allowsMultiple = [coder decodeBoolForKey:@"NSAllowsMultipleSelection"];
    if ([coder containsValueForKey:@"NSAllowsEmptySelection"])
        _allowsEmpty = [coder decodeBoolForKey:@"NSAllowsEmptySelection"];
    id colors = [coder containsValueForKey:@"NSBackgroundColors"] ? [coder decodeObjectForKey:@"NSBackgroundColors"] : nil;
    if ([colors isKindOfClass:[NSArray class]])
        _bgColors = [colors copy];
    if ([coder containsValueForKey:@"NSMaxNumberOfGridRows"])
        _maxRows = (NSUInteger)MAX([coder decodeIntegerForKey:@"NSMaxNumberOfGridRows"], 0);
    if ([coder containsValueForKey:@"NSMaxNumberOfGridColumns"])
        _maxCols = (NSUInteger)MAX([coder decodeIntegerForKey:@"NSMaxNumberOfGridColumns"], 0);
    if ([coder containsValueForKey:@"NSMinGridSize"])
        _minItem = [coder decodeSizeForKey:@"NSMinGridSize"];
    if ([coder containsValueForKey:@"NSMaxGridSize"])
        _maxItem = [coder decodeSizeForKey:@"NSMaxGridSize"];
    id layout = [coder containsValueForKey:@"NSCollectionViewLayout"] ? [coder decodeObjectForKey:@"NSCollectionViewLayout"]
                                                                       : nil;
    if ([layout isKindOfClass:[NSCollectionViewLayout class]])
        [self setCollectionViewLayout:layout];
    [self _syncLegacyLayout];
    return self;
}
- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSCollectionViewItem *item in [_visible allValues])
        [item _setCollectionView:nil];
    for (NSCollectionViewItem *item in _legacyItems)
        [item _setCollectionView:nil];
    [_layout _setCollectionView:nil];
    [_legacyLayout _setCollectionView:nil];
    [_layout release];
    [_legacyLayout release];
    [_backgroundView release];
    [_bgColors release];
    [_selection release];
    [_itemClasses release];
    [_itemNibs release];
    [_suppClasses release];
    [_suppNibs release];
    [_reuseItems release];
    [_reuseViews release];
    [_visible release];
    [_visibleSupp release];
    [_counts release];
    [_pending release];
    [_content release];
    [_prototype release];
    [_legacyItems release];
    [_anchor release];
    [_lead release];
    [_pressSelect release];
    [_pressDeselect release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)_modern { return _dataSource != nil; }
- (NSCollectionViewLayout *)_activeLayout
{
    if ([self _modern])
        return _layout;
    return _layout ?: _legacyLayout;
}

/* ---- properties ---- */

- (id)dataSource { return _dataSource; }
- (void)setDataSource:(id)dataSource
{
    _dataSource = dataSource;
    [self reloadData];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate
{
    _delegate = delegate;
    [[self _activeLayout] invalidateLayout];
}
- (NSCollectionViewLayout *)collectionViewLayout { return _layout; }
- (void)setCollectionViewLayout:(NSCollectionViewLayout *)layout
{
    if (layout == _layout)
        return;
    [_layout _setCollectionView:nil];
    [layout retain];
    [_layout release];
    _layout = layout;
    [_layout _setCollectionView:self];
    [self _discardSupplementaryViews];
    [self _layoutInvalidated];
}
- (NSView *)backgroundView { return _backgroundView; }
- (void)setBackgroundView:(NSView *)view
{
    if (view == _backgroundView)
        return;
    [_backgroundView removeFromSuperview];
    [view retain];
    [_backgroundView release];
    _backgroundView = view;
    if (view)
        [self addSubview:view positioned:NSWindowBelow relativeTo:nil];
    [self _setNeedsTile];
}
- (BOOL)backgroundViewScrollsWithContent { return _bgScrolls; }
- (void)setBackgroundViewScrollsWithContent:(BOOL)f
{
    _bgScrolls = f;
    [self _setNeedsTile];
}
- (NSArray *)backgroundColors
{
    return _bgColors ?: [NSArray arrayWithObject:[NSColor controlBackgroundColor]];
}
- (void)setBackgroundColors:(NSArray *)colors
{
    if (colors == _bgColors)
        return;
    [_bgColors release];
    _bgColors = [colors count] ? [colors copy] : nil;
    [self setNeedsDisplay:YES];
}
- (BOOL)isSelectable { return _selectable; }
- (void)setSelectable:(BOOL)f { _selectable = f; }
- (BOOL)allowsEmptySelection { return _allowsEmpty; }
- (void)setAllowsEmptySelection:(BOOL)f { _allowsEmpty = f; }
- (BOOL)allowsMultipleSelection { return _allowsMultiple; }
- (void)setAllowsMultipleSelection:(BOOL)f { _allowsMultiple = f; }
- (BOOL)isFirstResponder { return [[self window] firstResponder] == self; }
- (BOOL)acceptsFirstResponder { return _selectable; }

/* ---- counts ---- */

- (void)_loadCounts
{
    if (_countsValid)
        return;
    _countsValid = YES;
    [_counts removeAllObjects];
    if (![self _modern]) {
        [_counts addObject:[NSNumber numberWithInteger:(NSInteger)[_content count]]];
        return;
    }
    NSInteger sections = 1;
    if ([_dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)])
        sections = MAX([_dataSource numberOfSectionsInCollectionView:self], 0);
    for (NSInteger s = 0; s < sections; s++)
        [_counts addObject:[NSNumber numberWithInteger:MAX([_dataSource collectionView:self numberOfItemsInSection:s], 0)]];
}
- (NSInteger)numberOfSections
{
    [self _loadCounts];
    return (NSInteger)[_counts count];
}
- (NSInteger)numberOfItemsInSection:(NSInteger)section
{
    [self _loadCounts];
    if (section < 0 || section >= (NSInteger)[_counts count])
        return 0;
    return [[_counts objectAtIndex:(NSUInteger)section] integerValue];
}
- (BOOL)_validPath:(NSIndexPath *)p
{
    return [p length] >= 2 && [p item] >= 0 && [p item] < [self numberOfItemsInSection:[p section]];
}
/* All the index paths, in order. */
- (NSArray *)_allPaths
{
    NSMutableArray *all = [NSMutableArray array];
    NSInteger sections = [self numberOfSections];
    for (NSInteger s = 0; s < sections; s++) {
        NSInteger n = [self numberOfItemsInSection:s];
        for (NSInteger i = 0; i < n; i++)
            [all addObject:IP(s, i)];
    }
    return all;
}

/* ---- the layout's view of things ---- */

- (NSClipView *)_clip
{
    NSView *sv = [self superview];
    return [sv isKindOfClass:[NSClipView class]] && [(NSClipView *)sv documentView] == self ? (NSClipView *)sv : nil;
}
- (NSSize)_layoutSize
{
    NSClipView *clip = [self _clip];
    return clip ? [clip bounds].size : [self bounds].size;
}
- (NSRect)_visibleArea
{
    if ([self window])
        return [self visibleRect];
    NSClipView *clip = [self _clip];
    if (clip)
        return NSIntersectionRect([self convertRect:[clip bounds] fromView:clip], [self bounds]);
    return [self bounds];
}
- (NSSize)_defaultItemSize
{
    NSSize s = _minItem;
    NSView *pv = [_prototype view];
    if (s.width <= 0 || s.height <= 0) {
        NSSize p = pv ? [pv frame].size : NSMakeSize(50, 50);
        if (s.width <= 0)
            s.width = p.width;
        if (s.height <= 0)
            s.height = p.height;
    }
    return s;
}
- (void)_syncLegacyLayout
{
    [_legacyLayout setMaximumNumberOfRows:_maxRows];
    [_legacyLayout setMaximumNumberOfColumns:_maxCols];
    [_legacyLayout setMinimumItemSize:_minItem];
    [_legacyLayout setMaximumItemSize:_maxItem];
}
- (void)_layoutInvalidated { [self _setNeedsTile]; }
- (void)_setNeedsTile
{
    _needsTile = YES;
    [self setNeedsDisplay:YES];
    if (!_tileScheduled) {
        _tileScheduled = YES;
        [self performSelector:@selector(_tileSoon) withObject:nil afterDelay:0];
    }
}
- (void)_tileSoon
{
    _tileScheduled = NO;
    [self _tileIfNeeded];
}
- (void)_tileIfNeeded
{
    if (_needsTile && !_tiling)
        [self _tile];
}

/* ---- making items and views ---- */

- (void)registerClass:(Class)itemClass forItemWithIdentifier:(NSString *)identifier
{
    if (!identifier)
        return;
    [_itemNibs removeObjectForKey:identifier];
    if (itemClass)
        [_itemClasses setObject:itemClass forKey:identifier];
    else
        [_itemClasses removeObjectForKey:identifier];
}
- (void)registerNib:(NSNib *)nib forItemWithIdentifier:(NSString *)identifier
{
    if (!identifier)
        return;
    [_itemClasses removeObjectForKey:identifier];
    if (nib)
        [_itemNibs setObject:nib forKey:identifier];
    else
        [_itemNibs removeObjectForKey:identifier];
}
static NSString *supp_key(NSString *kind, NSString *identifier)
{
    return [NSString stringWithFormat:@"%@\n%@", kind ?: @"", identifier ?: @""];
}
- (void)registerClass:(Class)viewClass forSupplementaryViewOfKind:(NSString *)kind withIdentifier:(NSString *)identifier
{
    NSString *k = supp_key(kind, identifier);
    [_suppNibs removeObjectForKey:k];
    if (viewClass)
        [_suppClasses setObject:viewClass forKey:k];
    else
        [_suppClasses removeObjectForKey:k];
}
- (void)registerNib:(NSNib *)nib forSupplementaryViewOfKind:(NSString *)kind withIdentifier:(NSString *)identifier
{
    NSString *k = supp_key(kind, identifier);
    [_suppClasses removeObjectForKey:k];
    if (nib)
        [_suppNibs setObject:nib forKey:k];
    else
        [_suppNibs removeObjectForKey:k];
}

/* The first top-level object of a nib that is of a class. */
static id from_nib(NSNib *nib, Class cls)
{
    NSArray *top = nil;
    if (![nib instantiateWithOwner:nil topLevelObjects:&top])
        return nil;
    for (id o in top)
        if ([o isKindOfClass:cls])
            return o;
    return nil;
}

- (NSCollectionViewItem *)makeItemWithIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray *queue = identifier ? [_reuseItems objectForKey:identifier] : nil;
    NSCollectionViewItem *item = nil;
    if ([queue count]) {
        item = [[[queue lastObject] retain] autorelease];
        [queue removeLastObject];
        [item prepareForReuse];
        return item;
    }
    Class cls = identifier ? [_itemClasses objectForKey:identifier] : Nil;
    NSNib *nib = identifier ? [_itemNibs objectForKey:identifier] : nil;
    if (cls) {
        item = [[[cls alloc] init] autorelease];
    } else {
        if (!nib && identifier)
            nib = [[[NSNib alloc] initWithNibNamed:identifier bundle:nil] autorelease];
        item = nib ? from_nib(nib, [NSCollectionViewItem class]) : nil;
    }
    if (!item) {
        fprintf(stderr, "ferry: a collection view has no class or nib for items with the identifier \"%s\"\n",
                [identifier UTF8String] ?: "(none)");
        return nil;
    }
    [item setIdentifier:identifier];
    [item _setCollectionView:self];
    return item;
}

static const char reuse_key = 0;

- (NSView *)makeSupplementaryViewOfKind:(NSString *)kind withIdentifier:(NSString *)identifier
                           forIndexPath:(NSIndexPath *)indexPath
{
    NSString *k = supp_key(kind, identifier);
    NSMutableArray *queue = [_reuseViews objectForKey:k];
    if ([queue count]) {
        NSView *v = [[[queue lastObject] retain] autorelease];
        [queue removeLastObject];
        if ([v respondsToSelector:@selector(prepareForReuse)])
            [(id)v prepareForReuse];
        return v;
    }
    Class cls = [_suppClasses objectForKey:k];
    NSNib *nib = [_suppNibs objectForKey:k];
    NSView *v = nil;
    if (cls) {
        v = [[[cls alloc] initWithFrame:NSZeroRect] autorelease];
    } else {
        if (!nib && identifier)
            nib = [[[NSNib alloc] initWithNibNamed:identifier bundle:nil] autorelease];
        v = nib ? from_nib(nib, [NSView class]) : nil;
    }
    if (!v) {
        fprintf(stderr, "ferry: a collection view has no class or nib for %s views with the identifier \"%s\"\n",
                [kind UTF8String] ?: "supplementary", [identifier UTF8String] ?: "(none)");
        return nil;
    }
    [v setIdentifier:identifier];
    objc_setAssociatedObject(v, &reuse_key, k, OBJC_ASSOCIATION_COPY);
    return v;
}

/* An item or view leaving sight: off the view, and kept for reuse. */
- (void)_retireItem:(NSCollectionViewItem *)item at:(NSIndexPath *)path
{
    if (!item)
        return;
    [[item retain] autorelease];
    [[item view] removeFromSuperview];
    if ([item isSelected])
        [item setSelected:NO];
    [item setHighlightState:NSCollectionViewItemHighlightNone];
    if (path && [_delegate respondsToSelector:@selector(collectionView:didEndDisplayingItem:forRepresentedObjectAtIndexPath:)])
        [_delegate collectionView:self didEndDisplayingItem:item forRepresentedObjectAtIndexPath:path];
    NSString *ident = [item identifier];
    if (ident) {
        NSMutableArray *queue = [_reuseItems objectForKey:ident];
        if (!queue) {
            queue = [NSMutableArray array];
            [_reuseItems setObject:queue forKey:ident];
        }
        [queue addObject:item];
    }
}
- (void)_retireView:(NSView *)view kind:(NSString *)kind at:(NSIndexPath *)path
{
    [[view retain] autorelease];
    [view removeFromSuperview];
    if (path && [_delegate respondsToSelector:@selector(collectionView:didEndDisplayingSupplementaryView:forElementOfKind:atIndexPath:)])
        [_delegate collectionView:self didEndDisplayingSupplementaryView:view forElementOfKind:kind atIndexPath:path];
    NSString *k = objc_getAssociatedObject(view, &reuse_key);
    if (k) {
        NSMutableArray *queue = [_reuseViews objectForKey:k];
        if (!queue) {
            queue = [NSMutableArray array];
            [_reuseViews setObject:queue forKey:k];
        }
        [queue addObject:view];
    }
}
- (void)_discardItems
{
    NSDictionary *old = [[_visible copy] autorelease];
    [_visible removeAllObjects];
    for (NSIndexPath *p in old)
        [self _retireItem:[old objectForKey:p] at:p];
}
- (void)_discardSupplementaryViews
{
    NSDictionary *old = [[_visibleSupp copy] autorelease];
    [_visibleSupp removeAllObjects];
    for (NSString *kind in old) {
        NSDictionary *views = [old objectForKey:kind];
        for (NSIndexPath *p in views)
            [self _retireView:[views objectForKey:p] kind:kind at:p];
    }
}

/* ---- laying out ---- */

- (void)_placeItem:(NSCollectionViewItem *)item attributes:(NSCollectionViewLayoutAttributes *)a
{
    NSView *v = [item view];
    if (!v)
        return;
    if ([v superview] != self)
        [self addSubview:v];
    if (!NSEqualRects([v frame], [a frame]))
        [v setFrame:[a frame]];
    [v setHidden:[a isHidden]];
    [item applyLayoutAttributes:a];
}

- (void)_tile
{
    _tiling = YES;
    _needsTile = NO;
    @try {
        [self _loadCounts];
        NSCollectionViewLayout *layout = [self _activeLayout];
        [layout _prepareIfNeeded];
        /* as big as the content, and at least as the clip view */
        NSClipView *clip = [self _clip];
        if (clip && layout) {
            NSSize cs = [layout collectionViewContentSize], area = [clip bounds].size;
            NSSize want = NSMakeSize(fmax(cs.width, area.width), fmax(cs.height, area.height));
            if (!NSEqualSizes(want, [self frame].size))
                [self setFrameSize:want];
        }
        NSRect vis = [self _visibleArea];
        if ([self _modern])
            [self _tileModern:layout visible:vis];
        else
            [self _tileLegacy:layout];
        if (_backgroundView) {
            NSRect f = _bgScrolls ? [self bounds] : vis;
            if (!NSEqualRects([_backgroundView frame], f))
                [_backgroundView setFrame:f];
            if ([[self subviews] firstObject] != _backgroundView) {
                [[_backgroundView retain] autorelease];
                [_backgroundView removeFromSuperview];
                [self addSubview:_backgroundView positioned:NSWindowBelow relativeTo:nil];
            }
        }
    } @finally {
        _tiling = NO;
    }
}

- (void)_tileModern:(NSCollectionViewLayout *)layout visible:(NSRect)vis
{
    NSArray *attrs = layout ? [layout layoutAttributesForElementsInRect:vis] : [NSArray array];
    NSMutableSet *seenItems = [NSMutableSet set];
    NSMutableDictionary *seenSupp = [NSMutableDictionary dictionary];
    /* first what has left sight, so that what comes into sight can reuse it */
    for (NSCollectionViewLayoutAttributes *a in attrs) {
        if ([a representedElementCategory] == NSCollectionElementCategoryItem) {
            [seenItems addObject:[a indexPath]];
        } else if ([a representedElementKind]) {
            NSMutableSet *seen = [seenSupp objectForKey:[a representedElementKind]];
            if (!seen) {
                seen = [NSMutableSet set];
                [seenSupp setObject:seen forKey:[a representedElementKind]];
            }
            [seen addObject:[a indexPath]];
        }
    }
    for (NSIndexPath *p in [_visible allKeys])
        if (![seenItems containsObject:p]) {
            NSCollectionViewItem *item = [[[_visible objectForKey:p] retain] autorelease];
            [_visible removeObjectForKey:p];
            [self _retireItem:item at:p];
        }
    for (NSString *kind in [_visibleSupp allKeys]) {
        NSMutableDictionary *views = [_visibleSupp objectForKey:kind];
        NSSet *seen = [seenSupp objectForKey:kind];
        for (NSIndexPath *p in [views allKeys])
            if (![seen containsObject:p]) {
                NSView *v = [[[views objectForKey:p] retain] autorelease];
                [views removeObjectForKey:p];
                [self _retireView:v kind:kind at:p];
            }
    }

    for (NSCollectionViewLayoutAttributes *a in attrs) {
        NSIndexPath *p = [a indexPath];
        if ([a representedElementCategory] == NSCollectionElementCategoryItem) {
            if (![self _validPath:p])
                continue;
            NSCollectionViewItem *item = [_visible objectForKey:p];
            if (!item) {
                item = [_dataSource collectionView:self itemForRepresentedObjectAtIndexPath:p];
                if (!item)
                    continue;
                [item _setCollectionView:self];
                [_visible setObject:item forKey:p];
                if ([_delegate respondsToSelector:@selector(collectionView:willDisplayItem:forRepresentedObjectAtIndexPath:)])
                    [_delegate collectionView:self willDisplayItem:item forRepresentedObjectAtIndexPath:p];
            }
            BOOL sel = [_selection containsObject:p];
            if ([item isSelected] != sel)
                [item setSelected:sel];
            [self _placeItem:item attributes:a];
        } else if ([a representedElementCategory] == NSCollectionElementCategorySupplementaryView) {
            NSString *kind = [a representedElementKind];
            if (!kind)
                continue;
            NSMutableDictionary *views = [_visibleSupp objectForKey:kind];
            if (!views) {
                views = [NSMutableDictionary dictionary];
                [_visibleSupp setObject:views forKey:kind];
            }
            NSView *v = [views objectForKey:p];
            if (!v && [_dataSource respondsToSelector:@selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)]) {
                v = [_dataSource collectionView:self viewForSupplementaryElementOfKind:kind atIndexPath:p];
                if (v) {
                    [views setObject:v forKey:p];
                    if ([_delegate respondsToSelector:@selector(collectionView:willDisplaySupplementaryView:forElementKind:atIndexPath:)])
                        [_delegate collectionView:self willDisplaySupplementaryView:v forElementKind:kind atIndexPath:p];
                }
            }
            if (!v)
                continue;
            if ([v superview] != self)
                [self addSubview:v];
            if (!NSEqualRects([v frame], [a frame]))
                [v setFrame:[a frame]];
            if ([v respondsToSelector:@selector(applyLayoutAttributes:)])
                [(id)v applyLayoutAttributes:a];
        }
    }
}

- (void)_tileLegacy:(NSCollectionViewLayout *)layout
{
    NSUInteger n = [_legacyItems count];
    for (NSUInteger i = 0; i < n; i++) {
        NSCollectionViewItem *item = [_legacyItems objectAtIndex:i];
        NSCollectionViewLayoutAttributes *a = [layout layoutAttributesForItemAtIndexPath:IP(0, (NSInteger)i)];
        BOOL sel = [_selection containsObject:IP(0, (NSInteger)i)];
        if ([item isSelected] != sel)
            [item setSelected:sel];
        if (a)
            [self _placeItem:item attributes:a];
    }
}

- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen
{
    [self _tileIfNeeded];
    [super _drawContentInContext:ctx dirty:dirty screen:screen];
}
- (NSView *)hitTest:(NSPoint)p
{
    [self _tileIfNeeded];
    return [super hitTest:p];
}
- (void)layout
{
    [self _tileIfNeeded];
    [super layout];
}
- (void)setFrameSize:(NSSize)size
{
    NSSize old = [self frame].size;
    [super setFrameSize:size];
    if (_tiling || NSEqualSizes(old, size) || [self _clip])
        return;
    NSCollectionViewLayout *layout = [self _activeLayout];
    NSRect b = [self bounds];
    if ([layout shouldInvalidateLayoutForBoundsChange:b])
        [layout invalidateLayout];
    else
        [self _setNeedsTile];
}
- (void)_clipViewResized:(NSClipView *)clip
{
    if (_tiling)
        return;
    NSCollectionViewLayout *layout = [self _activeLayout];
    NSRect b = [clip bounds];
    if ([layout shouldInvalidateLayoutForBoundsChange:b])
        [layout invalidateLayout];
    [self _tile];
}
- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_observedClip)
        [nc removeObserver:self name:NSViewBoundsDidChangeNotification object:_observedClip];
    _observedClip = nil;
    NSClipView *clip = [self _clip];
    if (clip) {
        _observedClip = clip;
        [clip setPostsBoundsChangedNotifications:YES];
        [nc addObserver:self selector:@selector(_clipScrolled:) name:NSViewBoundsDidChangeNotification object:clip];
    }
    [[self _activeLayout] invalidateLayout];
}
- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self _setNeedsTile];
}
- (void)_clipScrolled:(NSNotification *)n
{
    if (!_tiling)
        [self _tile];
}

- (void)drawRect:(NSRect)rect
{
    NSArray *colors = [self backgroundColors];
    if (![colors count])
        return;
    [(NSColor *)[colors objectAtIndex:0] setFill];
    NSRectFill(rect);
    NSCollectionViewLayout *layout = [self _activeLayout];
    if ([colors count] > 1 && [layout isKindOfClass:[NSCollectionViewGridLayout class]]) {
        /* rows of the other colours in turn */
        CGFloat pitch = [(NSCollectionViewGridLayout *)layout _rowPitch];
        CGFloat y = [(NSCollectionViewGridLayout *)layout _firstRow];
        if (pitch <= 0)
            return;
        NSUInteger row = 0;
        for (; y < NSMaxY(rect); y += pitch, row++) {
            if (y + pitch < NSMinY(rect))
                continue;
            [(NSColor *)[colors objectAtIndex:row % [colors count]] setFill];
            NSRectFill(NSIntersectionRect(rect, NSMakeRect(NSMinX([self bounds]), y, [self bounds].size.width, pitch)));
        }
    }
}

/* ---- reloading and updates ---- */

- (void)reloadData
{
    if (![self _modern]) {
        [self _reloadLegacy];
        return;
    }
    [self _discardItems];
    [self _discardSupplementaryViews];
    _countsValid = NO;
    [self _loadCounts];
    for (NSIndexPath *p in [[_selection copy] autorelease])
        if (![self _validPath:p])
            [_selection removeObject:p];
    [[self _activeLayout] invalidateLayout];
    [self _setNeedsTile];
}

- (void)_queue:(AUpdate *)u
{
    if (!_pending)
        _pending = [[NSMutableArray alloc] init];
    [_pending addObject:u];
    if (!_batch)
        [self _applyPending];
}
static AUpdate *update_of(NSCollectionUpdateAction action, BOOL sections, NSArray *paths)
{
    AUpdate *u = [[[AUpdate alloc] init] autorelease];
    u->action = action;
    u->sections = sections;
    u->paths = [paths copy];
    return u;
}
static NSArray *section_numbers(NSIndexSet *set)
{
    NSMutableArray *a = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
      [a addObject:[NSNumber numberWithUnsignedInteger:i]];
    }];
    return a;
}
- (void)insertItemsAtIndexPaths:(NSSet *)paths
{
    [self _queue:update_of(NSCollectionUpdateActionInsert, NO, [paths allObjects])];
}
- (void)deleteItemsAtIndexPaths:(NSSet *)paths
{
    [self _queue:update_of(NSCollectionUpdateActionDelete, NO, [paths allObjects])];
}
- (void)reloadItemsAtIndexPaths:(NSSet *)paths
{
    [self _queue:update_of(NSCollectionUpdateActionReload, NO, [paths allObjects])];
}
- (void)insertSections:(NSIndexSet *)sections
{
    [self _queue:update_of(NSCollectionUpdateActionInsert, YES, section_numbers(sections))];
}
- (void)deleteSections:(NSIndexSet *)sections
{
    [self _queue:update_of(NSCollectionUpdateActionDelete, YES, section_numbers(sections))];
}
- (void)reloadSections:(NSIndexSet *)sections
{
    [self _queue:update_of(NSCollectionUpdateActionReload, YES, section_numbers(sections))];
}
- (void)moveItemAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    AUpdate *u = update_of(NSCollectionUpdateActionMove, NO, nil);
    u->from = [from retain];
    u->to = [to retain];
    [self _queue:u];
}
- (void)moveSection:(NSInteger)from toSection:(NSInteger)to
{
    AUpdate *u = update_of(NSCollectionUpdateActionMove, YES, nil);
    u->from = [IP(from, 0) retain];
    u->to = [IP(to, 0) retain];
    [self _queue:u];
}
- (void)performBatchUpdates:(void (^)(void))updates completionHandler:(void (^)(BOOL))completion
{
    _batch++;
    @try {
        if (updates)
            updates();
    } @finally {
        _batch--;
    }
    if (!_batch)
        [self _applyPending];
    if (completion)
        completion(YES);
}

/* Pairs of (what, where) in order of where. */
static NSComparisonResult (^by_place)(id, id) = ^NSComparisonResult(id a, id b) {
  return [(NSIndexPath *)[a objectAtIndex:1] compare:[b objectAtIndex:1]];
};

/* Applies the changes asked for since the last time: reloads and deletes
 * at the places from before, inserts and moves' ends at the places after,
 * the selection and the items in sight going with their places. */
- (void)_applyPending
{
    NSArray *ops = [[_pending copy] autorelease];
    [_pending removeAllObjects];
    if (![ops count])
        return;
    if (![self _modern]) {
        [self reloadData];
        return;
    }
    [self _loadCounts];
    NSMutableArray *updateItems = [NSMutableArray array];
    /* the places as they were */
    NSMutableArray *sections = [NSMutableArray array];
    for (NSUInteger s = 0; s < [_counts count]; s++) {
        NSMutableArray *slots = [NSMutableArray array];
        NSInteger n = [[_counts objectAtIndex:s] integerValue];
        for (NSInteger i = 0; i < n; i++) {
            ASlot *slot = [[ASlot alloc] init];
            NSIndexPath *p = IP((NSInteger)s, i);
            slot->was = [p retain];
            slot->selected = [_selection containsObject:p];
            slot->item = [[_visible objectForKey:p] retain];
            [slots addObject:slot];
            [slot release];
        }
        [sections addObject:slots];
    }
    for (NSIndexPath *p in [_visible allKeys])
        if (![self _validPath:p]) {
            [self _retireItem:[_visible objectForKey:p] at:p];
        }
    [_visible removeAllObjects];
    [self _discardSupplementaryViews];
    NSMutableArray *retire = [NSMutableArray array];
    ASlot * (^slotAt)(NSIndexPath *) = ^ASlot *(NSIndexPath *p) {
      if ([p section] < 0 || [p section] >= (NSInteger)[sections count])
          return nil;
      NSArray *slots = [sections objectAtIndex:(NSUInteger)[p section]];
      return [p item] >= 0 && [p item] < (NSInteger)[slots count] ? [slots objectAtIndex:(NSUInteger)[p item]] : nil;
    };
    void (^dropItem)(ASlot *) = ^(ASlot *slot) {
      if (slot->item) {
          [retire addObject:[NSArray arrayWithObjects:slot->item, slot->was, nil]];
          [slot->item release];
          slot->item = nil;
      }
    };
    NSMutableSet *removedSections = [NSMutableSet set];
    NSMutableArray *movedSlots = [NSMutableArray array], *movedSections = [NSMutableArray array];
    NSMutableArray *newSections = [NSMutableArray array], *newSlots = [NSMutableArray array];
    NSMutableSet *freshSections = [NSMutableSet set];
    for (AUpdate *u in ops) {
        if (u->action == NSCollectionUpdateActionReload) {
            for (id x in u->paths) {
                if (u->sections) {
                    NSUInteger s = [x unsignedIntegerValue];
                    if (s < [sections count])
                        for (ASlot *slot in [sections objectAtIndex:s])
                            dropItem(slot);
                } else {
                    ASlot *slot = slotAt(x);
                    if (slot)
                        dropItem(slot);
                }
            }
        } else if (u->action == NSCollectionUpdateActionDelete) {
            for (id x in u->paths) {
                if (u->sections) {
                    NSUInteger s = [x unsignedIntegerValue];
                    if (s < [sections count]) {
                        [removedSections addObject:[NSValue valueWithPointer:[sections objectAtIndex:s]]];
                        for (ASlot *slot in [sections objectAtIndex:s])
                            dropItem(slot);
                    }
                } else {
                    ASlot *slot = slotAt(x);
                    if (slot) {
                        slot->removed = YES;
                        dropItem(slot);
                    }
                }
            }
        } else if (u->action == NSCollectionUpdateActionMove) {
            if (u->sections) {
                NSUInteger s = (NSUInteger)[u->from section];
                if (s < [sections count]) {
                    NSMutableArray *sec = [sections objectAtIndex:s];
                    [removedSections addObject:[NSValue valueWithPointer:sec]];
                    [movedSections addObject:[NSArray arrayWithObjects:sec, u->to, nil]];
                }
            } else {
                ASlot *slot = slotAt(u->from);
                if (slot) {
                    slot->removed = YES;
                    [movedSlots addObject:[NSArray arrayWithObjects:slot, u->to, nil]];
                }
            }
        } else if (u->action == NSCollectionUpdateActionInsert) {
            for (id x in u->paths) {
                if (u->sections) {
                    NSMutableArray *fresh = [NSMutableArray array];
                    [freshSections addObject:[NSValue valueWithPointer:fresh]];
                    [newSections addObject:[NSArray arrayWithObjects:fresh, IP([x integerValue], 0), nil]];
                }
                else
                    [newSlots addObject:[NSArray arrayWithObjects:[[[ASlot alloc] init] autorelease], x, nil]];
            }
        }
        NSCollectionViewUpdateItem *ui = [[[NSCollectionViewUpdateItem alloc] init] autorelease];
        ui->_action = u->action;
        if (u->action == NSCollectionUpdateActionMove) {
            ui->_before = [u->from retain];
            ui->_after = [u->to retain];
        } else if ([u->paths count]) {
            id x = [u->paths objectAtIndex:0];
            NSIndexPath *p = u->sections ? [NSIndexPath indexPathWithIndex:[x unsignedIntegerValue]] : x;
            if (u->action == NSCollectionUpdateActionInsert)
                ui->_after = [p retain];
            else
                ui->_before = [p retain];
        }
        [updateItems addObject:ui];
    }
    /* out with what went, from the moved sections too */
    for (NSMutableArray *slots in sections) {
        NSMutableArray *keep = [NSMutableArray array];
        for (ASlot *slot in slots)
            if (!slot->removed)
                [keep addObject:slot];
        [slots setArray:keep];
    }
    NSMutableArray *kept = [NSMutableArray array];
    for (NSMutableArray *slots in sections)
        if (![removedSections containsObject:[NSValue valueWithPointer:slots]])
            [kept addObject:slots];
    [sections setArray:kept];
    /* in with what came, in order of their new places */
    [newSections addObjectsFromArray:movedSections];
    [newSections sortUsingComparator:by_place];
    for (NSArray *pair in newSections) {
        NSUInteger at = (NSUInteger)MAX([[pair objectAtIndex:1] section], 0);
        [sections insertObject:[pair objectAtIndex:0] atIndex:MIN(at, [sections count])];
    }
    [newSlots addObjectsFromArray:movedSlots];
    [newSlots sortUsingComparator:by_place];
    for (NSArray *pair in newSlots) {
        NSIndexPath *p = [pair objectAtIndex:1];
        ASlot *slot = [pair objectAtIndex:0];
        slot->removed = NO;
        if ([p section] < 0 || [p section] >= (NSInteger)[sections count]) {
            dropItem(slot);
            continue;
        }
        NSMutableArray *slots = [sections objectAtIndex:(NSUInteger)[p section]];
        [slots insertObject:slot atIndex:MIN((NSUInteger)MAX([p item], 0), [slots count])];
    }
    [[self _activeLayout] prepareForCollectionViewUpdates:updateItems];
    /* what the data source says now */
    _countsValid = NO;
    [self _loadCounts];
    BOOL mismatch = [sections count] != [_counts count];
    while ([sections count] < [_counts count])
        [sections addObject:[NSMutableArray array]];
    while ([sections count] > [_counts count]) {
        for (ASlot *slot in [sections lastObject])
            dropItem(slot);
        [sections removeLastObject];
    }
    [_selection removeAllObjects];
    for (NSUInteger s = 0; s < [sections count]; s++) {
        NSMutableArray *slots = [sections objectAtIndex:s];
        NSUInteger n = (NSUInteger)[[_counts objectAtIndex:s] integerValue];
        if ([slots count] != n && ![freshSections containsObject:[NSValue valueWithPointer:slots]])
            mismatch = YES;
        while ([slots count] < n)
            [slots addObject:[[[ASlot alloc] init] autorelease]];
        while ([slots count] > n) {
            dropItem([slots lastObject]);
            [slots removeLastObject];
        }
        for (NSUInteger i = 0; i < n; i++) {
            ASlot *slot = [slots objectAtIndex:i];
            NSIndexPath *p = IP((NSInteger)s, (NSInteger)i);
            if (slot->selected)
                [_selection addObject:p];
            if (slot->item)
                [_visible setObject:slot->item forKey:p];
        }
    }
    static BOOL told;
    if (mismatch && !told) {
        told = YES;
        fprintf(stderr, "ferry: a collection view's data source counts don't agree with the items and sections "
                        "inserted and deleted; the collection view follows the data source\n");
    }
    for (NSArray *pair in retire)
        [self _retireItem:[pair objectAtIndex:0] at:[pair objectAtIndex:1]];
    [[self _activeLayout] invalidateLayout];
    [[self _activeLayout] finalizeCollectionViewUpdates];
    [self _setNeedsTile];
}

/* ---- finding items ---- */

- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)p
{
    if (![self _modern])
        return [p section] == 0 ? [self itemAtIndex:(NSUInteger)[p item]] : nil;
    [self _tileIfNeeded];
    return [_visible objectForKey:p];
}
- (NSArray *)visibleItems
{
    [self _tileIfNeeded];
    if (![self _modern]) {
        NSMutableArray *a = [NSMutableArray array];
        NSRect vis = [self _visibleArea];
        for (NSCollectionViewItem *item in _legacyItems)
            if (NSIntersectsRect([[item view] frame], vis))
                [a addObject:item];
        return a;
    }
    NSMutableArray *a = [NSMutableArray array];
    for (NSIndexPath *p in [[_visible allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [a addObject:[_visible objectForKey:p]];
    return a;
}
- (NSSet *)indexPathsForVisibleItems
{
    NSMutableSet *s = [NSMutableSet set];
    for (NSCollectionViewItem *item in [self visibleItems]) {
        NSIndexPath *p = [self indexPathForItem:item];
        if (p)
            [s addObject:p];
    }
    return s;
}
- (NSIndexPath *)indexPathForItem:(NSCollectionViewItem *)item
{
    if (![self _modern]) {
        NSUInteger i = [_legacyItems indexOfObjectIdenticalTo:item];
        return i == NSNotFound ? nil : IP(0, (NSInteger)i);
    }
    for (NSIndexPath *p in _visible)
        if ([_visible objectForKey:p] == item)
            return p;
    return nil;
}
- (NSIndexPath *)indexPathForItemAtPoint:(NSPoint)point
{
    [self _loadCounts];
    NSCollectionViewLayout *layout = [self _activeLayout];
    NSArray *attrs = [layout layoutAttributesForElementsInRect:NSMakeRect(point.x - 0.5, point.y - 0.5, 1, 1)];
    NSIndexPath *best = nil;
    NSInteger z = NSIntegerMin;
    for (NSCollectionViewLayoutAttributes *a in attrs)
        if ([a representedElementCategory] == NSCollectionElementCategoryItem && ![a isHidden] &&
            NSPointInRect(point, [a frame]) && [a zIndex] >= z && [self _validPath:[a indexPath]]) {
            best = [a indexPath];
            z = [a zIndex];
        }
    return best;
}
- (NSView *)supplementaryViewForElementKind:(NSString *)kind atIndexPath:(NSIndexPath *)p
{
    [self _tileIfNeeded];
    return [[_visibleSupp objectForKey:kind] objectForKey:p];
}
- (NSArray *)visibleSupplementaryViewsOfKind:(NSString *)kind
{
    [self _tileIfNeeded];
    NSDictionary *views = [_visibleSupp objectForKey:kind];
    NSMutableArray *a = [NSMutableArray array];
    for (NSIndexPath *p in [[views allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [a addObject:[views objectForKey:p]];
    return a;
}
- (NSSet *)indexPathsForVisibleSupplementaryElementsOfKind:(NSString *)kind
{
    [self _tileIfNeeded];
    return [NSSet setWithArray:[[_visibleSupp objectForKey:kind] allKeys] ?: [NSArray array]];
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p
{
    [self _loadCounts];
    return [[self _activeLayout] layoutAttributesForItemAtIndexPath:p];
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryElementOfKind:(NSString *)kind
                                                                        atIndexPath:(NSIndexPath *)p
{
    [self _loadCounts];
    return [[self _activeLayout] layoutAttributesForSupplementaryViewOfKind:kind atIndexPath:p];
}

/* ---- selection ---- */

- (NSSet *)selectionIndexPaths { return [[_selection copy] autorelease]; }
- (void)_showSelection
{
    for (NSIndexPath *p in _visible) {
        NSCollectionViewItem *item = [_visible objectForKey:p];
        BOOL sel = [_selection containsObject:p];
        if ([item isSelected] != sel)
            [item setSelected:sel];
    }
    for (NSUInteger i = 0; i < [_legacyItems count]; i++) {
        NSCollectionViewItem *item = [_legacyItems objectAtIndex:i];
        BOOL sel = [_selection containsObject:IP(0, (NSInteger)i)];
        if ([item isSelected] != sel)
            [item setSelected:sel];
    }
    [self setNeedsDisplay:YES];
}
- (void)_setSelection:(NSSet *)paths
{
    if ([paths isEqualToSet:_selection]) {
        [self _showSelection];
        return;
    }
    [self willChangeValueForKey:@"selectionIndexPaths"];
    [self willChangeValueForKey:@"selectionIndexes"];
    [_selection setSet:paths ?: [NSSet set]];
    [self didChangeValueForKey:@"selectionIndexes"];
    [self didChangeValueForKey:@"selectionIndexPaths"];
    [self _showSelection];
}
- (void)setSelectionIndexPaths:(NSSet *)paths
{
    NSMutableSet *valid = [NSMutableSet set];
    for (NSIndexPath *p in paths)
        if ([self _validPath:p])
            [valid addObject:p];
    [self _setSelection:valid];
}
- (NSIndexSet *)selectionIndexes
{
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    for (NSIndexPath *p in _selection)
        if ([p section] == 0)
            [set addIndex:(NSUInteger)[p item]];
    return set;
}
- (void)setSelectionIndexes:(NSIndexSet *)indexes
{
    NSMutableSet *paths = [NSMutableSet set];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
      [paths addObject:IP(0, (NSInteger)i)];
    }];
    [self setSelectionIndexPaths:paths];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:@"selectionIndexes"] || [key isEqualToString:@"selectionIndexPaths"])
        return NO;
    return [super automaticallyNotifiesObserversForKey:key];
}
- (void)selectItemsAtIndexPaths:(NSSet *)paths scrollPosition:(NSCollectionViewScrollPosition)position
{
    NSMutableSet *next = _allowsMultiple ? [[_selection mutableCopy] autorelease] : [NSMutableSet set];
    NSArray *sorted = [[paths allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSIndexPath *p in sorted) {
        if (![self _validPath:p])
            continue;
        if (!_allowsMultiple)
            [next removeAllObjects];
        [next addObject:p];
    }
    [self _setSelection:next];
    if (position != NSCollectionViewScrollPositionNone)
        [self scrollToItemsAtIndexPaths:paths scrollPosition:position];
}
- (void)deselectItemsAtIndexPaths:(NSSet *)paths
{
    NSMutableSet *next = [[_selection mutableCopy] autorelease];
    [next minusSet:paths];
    [self _setSelection:next];
}

/* A change the user makes: the delegate may narrow what is selected and
 * deselected, and is told what was; a bound selection is written back. */
- (NSSet *)_askToSelect:(NSSet *)add
{
    if ([add count] && [_delegate respondsToSelector:@selector(collectionView:shouldSelectItemsAtIndexPaths:)])
        add = [_delegate collectionView:self shouldSelectItemsAtIndexPaths:add] ?: [NSSet set];
    return add;
}
- (NSSet *)_askToDeselect:(NSSet *)remove
{
    if ([remove count] && [_delegate respondsToSelector:@selector(collectionView:shouldDeselectItemsAtIndexPaths:)])
        remove = [_delegate collectionView:self shouldDeselectItemsAtIndexPaths:remove] ?: [NSSet set];
    return remove;
}
- (BOOL)_userSelect:(NSSet *)next
{
    if (!_selectable)
        return NO;
    NSMutableSet *add = [[next mutableCopy] autorelease];
    [add minusSet:_selection];
    NSMutableSet *remove = [[_selection mutableCopy] autorelease];
    [remove minusSet:next];
    NSSet *removing = [self _askToDeselect:remove];
    NSSet *adding = [self _askToSelect:add];
    NSMutableSet *result = [[_selection mutableCopy] autorelease];
    [result minusSet:removing];
    [result unionSet:adding];
    if (![result count] && !_allowsEmpty && [_selection count])
        return NO;
    if ([result isEqualToSet:_selection])
        return NO;
    NSMutableSet *deselected = [[_selection mutableCopy] autorelease];
    [deselected minusSet:result];
    NSMutableSet *selected = [[result mutableCopy] autorelease];
    [selected minusSet:_selection];
    [self _setSelection:result];
    if ([deselected count] && [_delegate respondsToSelector:@selector(collectionView:didDeselectItemsAtIndexPaths:)])
        [_delegate collectionView:self didDeselectItemsAtIndexPaths:deselected];
    if ([selected count] && [_delegate respondsToSelector:@selector(collectionView:didSelectItemsAtIndexPaths:)])
        [_delegate collectionView:self didSelectItemsAtIndexPaths:selected];
    ABindingPush(self, NSSelectionIndexesBinding);
    return YES;
}
- (IBAction)selectAll:(id)sender
{
    if (_selectable && _allowsMultiple)
        [self _userSelect:[NSSet setWithArray:[self _allPaths]]];
}
- (IBAction)deselectAll:(id)sender
{
    if (_selectable)
        [self _userSelect:[NSSet set]];
}

/* The highlight a press gives, asked of and told to the delegate. */
- (NSSet *)_highlight:(NSSet *)paths state:(NSCollectionViewItemHighlightState)state
{
    if (![paths count])
        return paths;
    if ([_delegate respondsToSelector:@selector(collectionView:shouldChangeItemsAtIndexPaths:toHighlightState:)])
        paths = [_delegate collectionView:self shouldChangeItemsAtIndexPaths:paths toHighlightState:state] ?: [NSSet set];
    for (NSIndexPath *p in paths)
        [[self itemAtIndexPath:p] setHighlightState:state];
    if ([paths count] && [_delegate respondsToSelector:@selector(collectionView:didChangeItemsAtIndexPaths:toHighlightState:)])
        [_delegate collectionView:self didChangeItemsAtIndexPaths:paths toHighlightState:state];
    return paths;
}

/* The items in flat order from one to another, both included. */
- (NSArray *)_pathsFrom:(NSIndexPath *)a to:(NSIndexPath *)b
{
    NSArray *all = [self _allPaths];
    NSUInteger i = [all indexOfObject:a], j = [all indexOfObject:b];
    if (i == NSNotFound || j == NSNotFound)
        return b ? [NSArray arrayWithObject:b] : [NSArray array];
    return [all subarrayWithRange:NSMakeRange(MIN(i, j), (i > j ? i - j : j - i) + 1)];
}
- (void)_setAnchor:(NSIndexPath *)p
{
    [p retain];
    [_anchor release];
    _anchor = p;
}
- (void)_setLead:(NSIndexPath *)p
{
    [p retain];
    [_lead release];
    _lead = p;
}

- (void)mouseDown:(NSEvent *)e
{
    [self _tileIfNeeded];
    if (!_selectable) {
        [super mouseDown:e];
        return;
    }
    if ([[self window] firstResponder] != self && [self acceptsFirstResponder])
        [[self window] makeFirstResponder:self];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSIndexPath *hit = [self indexPathForItemAtPoint:p];
    NSEventModifierFlags m = [e modifierFlags];
    NSMutableSet *next;
    if (!hit) {
        next = _allowsEmpty ? [NSMutableSet set] : [[_selection mutableCopy] autorelease];
    } else if ((m & NSEventModifierFlagCommand) && _allowsMultiple) {
        next = [[_selection mutableCopy] autorelease];
        if ([next containsObject:hit])
            [next removeObject:hit];
        else
            [next addObject:hit];
        [self _setAnchor:hit];
    } else if ((m & NSEventModifierFlagShift) && _allowsMultiple && _anchor) {
        next = [NSMutableSet setWithArray:[self _pathsFrom:_anchor to:hit]];
    } else {
        next = [NSMutableSet setWithObject:hit];
        [self _setAnchor:hit];
    }
    if (hit)
        [self _setLead:hit];
    NSMutableSet *add = [[next mutableCopy] autorelease];
    [add minusSet:_selection];
    NSMutableSet *remove = [[_selection mutableCopy] autorelease];
    [remove minusSet:next];
    [_pressSelect release];
    [_pressDeselect release];
    _pressSelect = [[self _highlight:add state:NSCollectionViewItemHighlightForSelection] retain];
    _pressDeselect = [[self _highlight:remove state:NSCollectionViewItemHighlightForDeselection] retain];
    _pressed = YES;
}
- (void)_endPress
{
    if (!_pressed)
        return;
    _pressed = NO;
    NSMutableSet *lit = [NSMutableSet setWithSet:_pressSelect ?: [NSSet set]];
    [lit unionSet:_pressDeselect ?: [NSSet set]];
    [self _highlight:lit state:NSCollectionViewItemHighlightNone];
    NSMutableSet *next = [[_selection mutableCopy] autorelease];
    [next minusSet:_pressDeselect ?: [NSSet set]];
    [next unionSet:_pressSelect ?: [NSSet set]];
    [_pressSelect release];
    [_pressDeselect release];
    _pressSelect = _pressDeselect = nil;
    [self _userSelect:next];
}
- (void)mouseUp:(NSEvent *)e
{
    if (_pressed)
        [self _endPress];
    else
        [super mouseUp:e];
}

/* ---- keys ---- */

- (void)keyDown:(NSEvent *)e
{
    if (_selectable)
        [self interpretKeyEvents:[NSArray arrayWithObject:e]];
    else
        [super keyDown:e];
}
- (void)insertText:(id)string {}
- (NSIndexPath *)_from
{
    if (_lead && [_selection containsObject:_lead])
        return _lead;
    return [[[_selection allObjects] sortedArrayUsingSelector:@selector(compare:)] lastObject];
}
/* The nearest item in a direction (dx, dy), by the layout's frames. */
- (NSIndexPath *)_neighbourOf:(NSIndexPath *)from dx:(int)dx dy:(int)dy
{
    NSArray *all = [self _allPaths];
    if (![all count])
        return nil;
    if (!from)
        return dx < 0 || dy < 0 ? [all lastObject] : [all objectAtIndex:0];
    NSCollectionViewLayout *layout = [self _activeLayout];
    NSRect f = [[layout layoutAttributesForItemAtIndexPath:from] frame];
    NSPoint c = NSMakePoint(NSMidX(f), NSMidY(f));
    NSIndexPath *best = nil;
    CGFloat bestScore = INFINITY;
    for (NSIndexPath *p in all) {
        if ([p isEqual:from])
            continue;
        NSCollectionViewLayoutAttributes *a = [layout layoutAttributesForItemAtIndexPath:p];
        if (!a || [a isHidden])
            continue;
        NSRect g = [a frame];
        CGFloat along, off;
        if (dx) {
            if (NSMaxY(g) <= NSMinY(f) || NSMinY(g) >= NSMaxY(f))
                continue; /* on another line */
            along = (NSMidX(g) - c.x) * dx;
            off = fabs(NSMidY(g) - c.y);
        } else {
            along = (NSMidY(g) - c.y) * dy;
            off = fabs(NSMidX(g) - c.x);
        }
        if (along <= 0.5)
            continue;
        CGFloat score = along * 4 + off;
        if (score < bestScore) {
            bestScore = score;
            best = p;
        }
    }
    if (!best && dx) {
        /* the end of a line: on to the next item in order, or back */
        NSUInteger i = [all indexOfObject:from];
        if (i != NSNotFound && dx > 0 && i + 1 < [all count])
            best = [all objectAtIndex:i + 1];
        else if (i != NSNotFound && dx < 0 && i > 0)
            best = [all objectAtIndex:i - 1];
    }
    return best;
}
- (void)_moveDx:(int)dx dy:(int)dy extending:(BOOL)extending
{
    NSIndexPath *to = [self _neighbourOf:[self _from] dx:dx dy:dy];
    if (!to)
        return;
    NSSet *next;
    if (extending && _allowsMultiple) {
        if (!_anchor)
            [self _setAnchor:[self _from] ?: to];
        next = [NSSet setWithArray:[self _pathsFrom:_anchor to:to]];
    } else {
        next = [NSSet setWithObject:to];
        [self _setAnchor:to];
    }
    [self _setLead:to];
    [self _userSelect:next];
    [self scrollToItemsAtIndexPaths:[NSSet setWithObject:to]
                     scrollPosition:NSCollectionViewScrollPositionNearestHorizontalEdge |
                                    NSCollectionViewScrollPositionNearestVerticalEdge];
}
- (void)moveLeft:(id)sender { [self _moveDx:-1 dy:0 extending:NO]; }
- (void)moveRight:(id)sender { [self _moveDx:1 dy:0 extending:NO]; }
- (void)moveUp:(id)sender { [self _moveDx:0 dy:-1 extending:NO]; }
- (void)moveDown:(id)sender { [self _moveDx:0 dy:1 extending:NO]; }
- (void)moveLeftAndModifySelection:(id)sender { [self _moveDx:-1 dy:0 extending:YES]; }
- (void)moveRightAndModifySelection:(id)sender { [self _moveDx:1 dy:0 extending:YES]; }
- (void)moveUpAndModifySelection:(id)sender { [self _moveDx:0 dy:-1 extending:YES]; }
- (void)moveDownAndModifySelection:(id)sender { [self _moveDx:0 dy:1 extending:YES]; }

/* ---- scrolling ---- */

- (void)scrollToItemsAtIndexPaths:(NSSet *)paths scrollPosition:(NSCollectionViewScrollPosition)position
{
    [self _tileIfNeeded];
    NSRect u = NSZeroRect;
    BOOL any = NO;
    for (NSIndexPath *p in paths) {
        NSCollectionViewLayoutAttributes *a = [self layoutAttributesForItemAtIndexPath:p];
        if (!a)
            continue;
        u = any ? NSUnionRect(u, [a frame]) : [a frame];
        any = YES;
    }
    NSClipView *clip = [self _clip];
    if (!any || !clip || position == NSCollectionViewScrollPositionNone)
        return;
    NSRect vis = [self convertRect:[clip bounds] fromView:clip];
    NSPoint o = vis.origin;
    if (position & NSCollectionViewScrollPositionTop)
        o.y = NSMinY(u);
    else if (position & NSCollectionViewScrollPositionCenteredVertically)
        o.y = NSMidY(u) - vis.size.height / 2;
    else if (position & NSCollectionViewScrollPositionBottom)
        o.y = NSMaxY(u) - vis.size.height;
    else if (position & NSCollectionViewScrollPositionNearestHorizontalEdge) {
        /* the nearer of the top and bottom edges, if not in sight already */
        if (NSMinY(u) < NSMinY(vis))
            o.y = NSMinY(u);
        else if (NSMaxY(u) > NSMaxY(vis))
            o.y = fmin(NSMinY(u), NSMaxY(u) - vis.size.height);
    }
    if (position & (NSCollectionViewScrollPositionLeft | NSCollectionViewScrollPositionLeadingEdge))
        o.x = NSMinX(u);
    else if (position & NSCollectionViewScrollPositionCenteredHorizontally)
        o.x = NSMidX(u) - vis.size.width / 2;
    else if (position & (NSCollectionViewScrollPositionRight | NSCollectionViewScrollPositionTrailingEdge))
        o.x = NSMaxX(u) - vis.size.width;
    else if (position & NSCollectionViewScrollPositionNearestVerticalEdge) {
        if (NSMinX(u) < NSMinX(vis))
            o.x = NSMinX(u);
        else if (NSMaxX(u) > NSMaxX(vis))
            o.x = fmin(NSMinX(u), NSMaxX(u) - vis.size.width);
    }
    NSRect target = [self convertRect:NSMakeRect(o.x, o.y, vis.size.width, vis.size.height) toView:clip];
    [clip scrollToPoint:target.origin];
    [self _tile];
}

- (IBAction)toggleSectionCollapse:(id)sender
{
    NSCollectionViewFlowLayout *flow = (id)[self _activeLayout];
    if (![flow isKindOfClass:[NSCollectionViewFlowLayout class]] || ![sender isKindOfClass:[NSView class]])
        return;
    NSDictionary *headers = [_visibleSupp objectForKey:NSCollectionElementKindSectionHeader];
    for (NSView *v = sender; v && v != self; v = [v superview])
        for (NSIndexPath *p in headers)
            if ([headers objectForKey:p] == v) {
                NSUInteger s = (NSUInteger)[p section];
                if ([flow sectionAtIndexIsCollapsed:s])
                    [flow expandSectionAtIndex:s];
                else
                    [flow collapseSectionAtIndex:s];
                return;
            }
}

/* ---- the older way ---- */

- (NSArray *)content { return _content ?: [NSArray array]; }
- (void)setContent:(NSArray *)content
{
    if (content == _content)
        return;
    id wasContent = _content;
    _content = [content copy];
    [wasContent release];
    [self _reloadLegacy];
}
- (NSCollectionViewItem *)itemPrototype { return _prototype; }
- (void)setItemPrototype:(NSCollectionViewItem *)prototype
{
    if (prototype == _prototype)
        return;
    [prototype retain];
    [_prototype release];
    _prototype = prototype;
    /* the items are made again from the new prototype */
    for (NSCollectionViewItem *item in _legacyItems) {
        [[item view] removeFromSuperview];
        [item _setCollectionView:nil];
    }
    [_legacyItems removeAllObjects];
    [self _reloadLegacy];
}
- (NSCollectionViewItem *)newItemForRepresentedObject:(id)object
{
    if (!_prototype)
        return nil;
    NSCollectionViewItem *item = [_prototype copy];
    [item setRepresentedObject:object];
    return item;
}
/* An item for each content object: kept for an object that is still
 * there, made for a new one. */
- (void)_reloadLegacy
{
    if ([self _modern])
        return;
    NSArray *content = [self content];
    NSMutableArray *old = [[_legacyItems mutableCopy] autorelease];
    NSMutableArray *items = [NSMutableArray array];
    for (id object in content) {
        NSCollectionViewItem *item = nil;
        for (NSUInteger i = 0; i < [old count]; i++)
            if ([[old objectAtIndex:i] representedObject] == object) {
                item = [old objectAtIndex:i];
                [items addObject:item];
                [old removeObjectAtIndex:i];
                break;
            }
        if (item)
            continue;
        item = [self newItemForRepresentedObject:object];
        if (!item)
            continue;
        [item _setCollectionView:self];
        [items addObject:item];
        [item release];
    }
    for (NSCollectionViewItem *item in old) {
        [[item view] removeFromSuperview];
        [item _setCollectionView:nil];
    }
    [_legacyItems setArray:items];
    _countsValid = NO;
    NSMutableSet *keep = [NSMutableSet set];
    for (NSIndexPath *p in _selection)
        if ([p section] == 0 && [p item] < (NSInteger)[items count])
            [keep addObject:p];
    if (![keep isEqualToSet:_selection])
        [self _setSelection:keep];
    [[self _activeLayout] invalidateLayout];
    [self _setNeedsTile];
}
- (NSCollectionViewItem *)itemAtIndex:(NSUInteger)index
{
    if ([self _modern])
        return [self itemAtIndexPath:IP(0, (NSInteger)index)];
    [self _tileIfNeeded];
    return index < [_legacyItems count] ? [_legacyItems objectAtIndex:index] : nil;
}
- (NSRect)frameForItemAtIndex:(NSUInteger)index
{
    NSCollectionViewLayoutAttributes *a = [self layoutAttributesForItemAtIndexPath:IP(0, (NSInteger)index)];
    return a ? [a frame] : NSZeroRect;
}
- (NSRect)frameForItemAtIndex:(NSUInteger)index withNumberOfItems:(NSUInteger)count
{
    return [_legacyLayout _frameAtIndex:index count:count];
}
- (NSUInteger)maxNumberOfRows { return _maxRows; }
- (void)setMaxNumberOfRows:(NSUInteger)n
{
    _maxRows = n;
    [self _syncLegacyLayout];
}
- (NSUInteger)maxNumberOfColumns { return _maxCols; }
- (void)setMaxNumberOfColumns:(NSUInteger)n
{
    _maxCols = n;
    [self _syncLegacyLayout];
}
- (NSSize)minItemSize { return _minItem; }
- (void)setMinItemSize:(NSSize)s
{
    _minItem = s;
    [self _syncLegacyLayout];
}
- (NSSize)maxItemSize { return _maxItem; }
- (void)setMaxItemSize:(NSSize)s
{
    _maxItem = s;
    [self _syncLegacyLayout];
}
@end

/* ---- index path sets ------------------------------------------------------------------- */

@implementation NSSet (NSCollectionViewAdditions)
+ (instancetype)setWithCollectionViewIndexPath:(NSIndexPath *)indexPath { return [self setWithObject:indexPath]; }
+ (instancetype)setWithCollectionViewIndexPaths:(NSArray *)indexPaths { return [self setWithArray:indexPaths]; }
- (void)enumerateIndexPathsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSIndexPath *, BOOL *))block
{
    NSArray *sorted = [[self allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [sorted enumerateObjectsWithOptions:opts & NSEnumerationReverse
                             usingBlock:^(id p, NSUInteger i, BOOL *stop) {
                               block(p, stop);
                             }];
}
@end
