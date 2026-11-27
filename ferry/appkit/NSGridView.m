/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's NSGridView (freemac 1.225, Ferry 0.49.0), written for Ferry from
 * Apple's public API documentation; what it does is in NSGridView.h.
 * A nib's grid (ferry-ibtool's) holds its rows, columns and cells, each
 * cell naming its row, column, content view and the cell it was merged
 * into, if any. */
#import "AInternal.h"
#include <objc/runtime.h>
#import <AppKit/NSGridView.h>

const CGFloat NSGridViewSizeForContent = 1.0e6;

@interface NSGridCell () {
@public
    NSView *_content;
    NSGridRow *_row;       /* not retained: the grid holds both */
    NSGridColumn *_column;
    NSGridCell *_head;     /* the cell this one was merged into, not retained */
    NSGridCellPlacement _x, _y;
    NSGridRowAlignment _align;
    NSArray *_custom;
}
@end

@interface NSGridRow () {
@public
    NSGridView *_grid;     /* not retained */
    NSMutableArray *_cells; /* one for each column */
    NSGridCellPlacement _y;
    NSGridRowAlignment _align;
    CGFloat _height, _top, _bottom;
    BOOL _hidden;
}
@end

@interface NSGridColumn () {
@public
    NSGridView *_grid;
    NSGridCellPlacement _x;
    CGFloat _width, _leading, _trailing;
    BOOL _hidden;
}
@end

@interface NSGridView () {
    NSMutableArray<NSGridRow *> *_rows;
    NSMutableArray<NSGridColumn *> *_columns;
    NSGridCellPlacement _x, _y;
    NSGridRowAlignment _align;
    CGFloat _rowSpacing, _columnSpacing;
    BOOL _laying;
}
- (void)_relayout;
@end

/* ---- cells ----------------------------------------------------------------------------- */

@implementation NSGridCell
+ (NSView *)emptyContentView
{
    static NSView *empty;
    if (!empty)
        empty = [[NSView alloc] initWithFrame:NSZeroRect];
    return empty;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super init]))
        return nil;
    id v = [c decodeObjectForKey:@"NSGridCellContentView"];
    _content = [v isKindOfClass:[NSView class]] ? [v retain] : nil;
    id r = [c decodeObjectForKey:@"NSGridCellRow"], col = [c decodeObjectForKey:@"NSGridCellColumn"];
    _row = [r isKindOfClass:[NSGridRow class]] ? r : nil;
    _column = [col isKindOfClass:[NSGridColumn class]] ? col : nil;
    id h = [c decodeObjectForKey:@"NSGridCellHead"];
    _head = [h isKindOfClass:[NSGridCell class]] ? h : nil;
    _x = [c decodeIntegerForKey:@"NSGridCellXPlacement"];
    _y = [c decodeIntegerForKey:@"NSGridCellYPlacement"];
    _align = [c decodeIntegerForKey:@"NSGridCellRowAlignment"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_content forKey:@"NSGridCellContentView"];
    [c encodeInteger:_x forKey:@"NSGridCellXPlacement"];
    [c encodeInteger:_y forKey:@"NSGridCellYPlacement"];
    [c encodeInteger:_align forKey:@"NSGridCellRowAlignment"];
}
- (void)dealloc
{
    [_content release];
    [_custom release];
    [super dealloc];
}
- (NSGridView *)_grid { return _row ? _row->_grid : nil; }
- (NSView *)contentView { return _content; }
- (void)setContentView:(NSView *)view
{
    if (view == _content)
        return;
    NSGridView *g = [self _grid];
    if ([_content superview] == g)
        [_content removeFromSuperview];
    id wasContent = _content;
    _content = [view retain];
    [wasContent release];
    if (g && view && view != [NSGridCell emptyContentView])
        [g addSubview:view];
    [g _relayout];
}
- (NSGridRow *)row { return _row; }
- (NSGridColumn *)column { return _column; }
- (NSGridCellPlacement)xPlacement { return _x; }
- (void)setXPlacement:(NSGridCellPlacement)p
{
    _x = p;
    [[self _grid] _relayout];
}
- (NSGridCellPlacement)yPlacement { return _y; }
- (void)setYPlacement:(NSGridCellPlacement)p
{
    _y = p;
    [[self _grid] _relayout];
}
- (NSGridRowAlignment)rowAlignment { return _align; }
- (void)setRowAlignment:(NSGridRowAlignment)a { _align = a; }
- (NSArray *)customPlacementConstraints { return _custom ?: @[]; }
- (void)setCustomPlacementConstraints:(NSArray *)constraints
{
    id wasCustom = _custom;
    _custom = [constraints copy];
    [wasCustom release];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSGridCell %p row %ld column %ld %@>", self,
                                      (long)[[self _grid] indexOfRow:_row],
                                      (long)[[self _grid] indexOfColumn:_column], _content];
}
@end

/* ---- rows and columns ------------------------------------------------------------------ */

@implementation NSGridRow
- (instancetype)init
{
    if ((self = [super init])) {
        _cells = [[NSMutableArray alloc] init];
        _height = NSGridViewSizeForContent;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self init]))
        return nil;
    _y = [c decodeIntegerForKey:@"NSGridRowYPlacement"];
    _align = [c decodeIntegerForKey:@"NSGridRowAlignment"];
    if ([c containsValueForKey:@"NSGridRowHeight"])
        _height = [c decodeDoubleForKey:@"NSGridRowHeight"];
    _top = [c decodeDoubleForKey:@"NSGridRowTopPadding"];
    _bottom = [c decodeDoubleForKey:@"NSGridRowBottomPadding"];
    _hidden = [c decodeBoolForKey:@"NSGridRowHidden"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeInteger:_y forKey:@"NSGridRowYPlacement"];
    [c encodeDouble:_height forKey:@"NSGridRowHeight"];
    [c encodeBool:_hidden forKey:@"NSGridRowHidden"];
}
- (void)dealloc
{
    [_cells release];
    [super dealloc];
}
- (NSGridView *)gridView { return _grid; }
- (NSInteger)numberOfCells { return (NSInteger)[_cells count]; }
- (NSGridCell *)cellAtIndex:(NSInteger)i { return _cells[(NSUInteger)i]; }
- (NSGridCellPlacement)yPlacement { return _y; }
- (void)setYPlacement:(NSGridCellPlacement)p
{
    _y = p;
    [_grid _relayout];
}
- (NSGridRowAlignment)rowAlignment { return _align; }
- (void)setRowAlignment:(NSGridRowAlignment)a { _align = a; }
- (CGFloat)height { return _height; }
- (void)setHeight:(CGFloat)h
{
    _height = h;
    [_grid _relayout];
}
- (CGFloat)topPadding { return _top; }
- (void)setTopPadding:(CGFloat)p
{
    _top = p;
    [_grid _relayout];
}
- (CGFloat)bottomPadding { return _bottom; }
- (void)setBottomPadding:(CGFloat)p
{
    _bottom = p;
    [_grid _relayout];
}
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)flag
{
    _hidden = flag;
    [_grid _relayout];
}
- (void)mergeCellsInRange:(NSRange)range
{
    NSInteger index = [_grid indexOfRow:self];
    if (index >= 0)
        [_grid mergeCellsInHorizontalRange:range verticalRange:NSMakeRange((NSUInteger)index, 1)];
}
@end

@implementation NSGridColumn
- (instancetype)init
{
    if ((self = [super init]))
        _width = NSGridViewSizeForContent;
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self init]))
        return nil;
    _x = [c decodeIntegerForKey:@"NSGridColumnXPlacement"];
    if ([c containsValueForKey:@"NSGridColumnWidth"])
        _width = [c decodeDoubleForKey:@"NSGridColumnWidth"];
    _leading = [c decodeDoubleForKey:@"NSGridColumnLeadingPadding"];
    _trailing = [c decodeDoubleForKey:@"NSGridColumnTrailingPadding"];
    _hidden = [c decodeBoolForKey:@"NSGridColumnHidden"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeInteger:_x forKey:@"NSGridColumnXPlacement"];
    [c encodeDouble:_width forKey:@"NSGridColumnWidth"];
    [c encodeBool:_hidden forKey:@"NSGridColumnHidden"];
}
- (NSGridView *)gridView { return _grid; }
- (NSInteger)numberOfCells { return [_grid numberOfRows]; }
- (NSGridCell *)cellAtIndex:(NSInteger)i
{
    return [_grid cellAtColumnIndex:[_grid indexOfColumn:self] rowIndex:i];
}
- (NSGridCellPlacement)xPlacement { return _x; }
- (void)setXPlacement:(NSGridCellPlacement)p
{
    _x = p;
    [_grid _relayout];
}
- (CGFloat)width { return _width; }
- (void)setWidth:(CGFloat)w
{
    _width = w;
    [_grid _relayout];
}
- (CGFloat)leadingPadding { return _leading; }
- (void)setLeadingPadding:(CGFloat)p
{
    _leading = p;
    [_grid _relayout];
}
- (CGFloat)trailingPadding { return _trailing; }
- (void)setTrailingPadding:(CGFloat)p
{
    _trailing = p;
    [_grid _relayout];
}
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)flag
{
    _hidden = flag;
    [_grid _relayout];
}
- (void)mergeCellsInRange:(NSRange)range
{
    NSInteger index = [_grid indexOfColumn:self];
    if (index >= 0)
        [_grid mergeCellsInHorizontalRange:NSMakeRange((NSUInteger)index, 1) verticalRange:range];
}
@end

/* ---- the grid -------------------------------------------------------------------------- */

static NSGridCell *new_cell(NSGridRow *row, NSGridColumn *column, NSView *view)
{
    NSGridCell *cell = [[[NSGridCell alloc] init] autorelease];
    cell->_row = row;
    cell->_column = column;
    if (view && view != [NSGridCell emptyContentView])
        cell->_content = [view retain];
    return cell;
}

/* a view's size as the grid sees it */
static NSSize size_of(NSView *v)
{
    if ([v isKindOfClass:[NSGridView class]] || [v isKindOfClass:[NSStackView class]])
        return [v fittingSize];
    NSSize s = [v intrinsicContentSize], f = [v frame].size;
    return NSMakeSize(s.width >= 0 ? s.width : f.width, s.height >= 0 ? s.height : f.height);
}

@implementation NSGridView
- (void)_setup
{
    _rows = [[NSMutableArray alloc] init];
    _columns = [[NSMutableArray alloc] init];
    _x = NSGridCellPlacementLeading;
    _y = NSGridCellPlacementBottom;
    _align = NSGridRowAlignmentNone;
    _rowSpacing = 6;
    _columnSpacing = 6;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setup];
    return self;
}
+ (instancetype)gridViewWithNumberOfColumns:(NSInteger)columns rows:(NSInteger)rows
{
    NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    for (NSInteger c = 0; c < columns; c++)
        [g addColumnWithViews:@[]];
    for (NSInteger r = 0; r < rows; r++)
        [g addRowWithViews:@[]];
    return g;
}
+ (instancetype)gridViewWithViews:(NSArray<NSArray<NSView *> *> *)rows
{
    NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
    for (NSArray *row in rows)
        [g addRowWithViews:row];
    [g setFrameSize:[g fittingSize]];
    return g;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    [self _setup];
    if ([c containsValueForKey:@"NSGridViewXPlacement"])
        _x = [c decodeIntegerForKey:@"NSGridViewXPlacement"];
    if ([c containsValueForKey:@"NSGridViewYPlacement"])
        _y = [c decodeIntegerForKey:@"NSGridViewYPlacement"];
    if ([c containsValueForKey:@"NSGridViewRowAlignment"])
        _align = [c decodeIntegerForKey:@"NSGridViewRowAlignment"];
    if ([c containsValueForKey:@"NSGridViewRowSpacing"])
        _rowSpacing = [c decodeDoubleForKey:@"NSGridViewRowSpacing"];
    if ([c containsValueForKey:@"NSGridViewColumnSpacing"])
        _columnSpacing = [c decodeDoubleForKey:@"NSGridViewColumnSpacing"];
    for (id r in [c decodeObjectForKey:@"NSGridViewRows"])
        if ([r isKindOfClass:[NSGridRow class]]) {
            ((NSGridRow *)r)->_grid = self;
            [_rows addObject:r];
        }
    for (id col in [c decodeObjectForKey:@"NSGridViewColumns"])
        if ([col isKindOfClass:[NSGridColumn class]]) {
            ((NSGridColumn *)col)->_grid = self;
            [_columns addObject:col];
        }
    /* every row has a cell for every column; the nib's cells go in their places */
    for (NSGridRow *r in _rows)
        for (NSGridColumn *col in _columns)
            [r->_cells addObject:new_cell(r, col, nil)];
    for (id cell in [c decodeObjectForKey:@"NSGridViewCells"]) {
        if (![cell isKindOfClass:[NSGridCell class]])
            continue;
        NSGridCell *gc = cell;
        NSUInteger ri = [_rows indexOfObjectIdenticalTo:gc->_row], ci = [_columns indexOfObjectIdenticalTo:gc->_column];
        if (ri == NSNotFound || ci == NSNotFound)
            continue;
        [_rows[ri]->_cells replaceObjectAtIndex:ci withObject:gc];
        if (gc->_content && [gc->_content superview] != self)
            [super addSubview:gc->_content];
    }
    [self _relayout];
    return self;
}
- (void)dealloc
{
    for (NSGridRow *r in _rows)
        r->_grid = nil;
    for (NSGridColumn *c in _columns)
        c->_grid = nil;
    [_rows release];
    [_columns release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }

- (NSInteger)numberOfRows { return (NSInteger)[_rows count]; }
- (NSInteger)numberOfColumns { return (NSInteger)[_columns count]; }
- (NSGridRow *)rowAtIndex:(NSInteger)i { return _rows[(NSUInteger)i]; }
- (NSInteger)indexOfRow:(NSGridRow *)row
{
    NSUInteger i = [_rows indexOfObjectIdenticalTo:row];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (NSGridColumn *)columnAtIndex:(NSInteger)i { return _columns[(NSUInteger)i]; }
- (NSInteger)indexOfColumn:(NSGridColumn *)column
{
    NSUInteger i = [_columns indexOfObjectIdenticalTo:column];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (NSGridCell *)cellAtColumnIndex:(NSInteger)c rowIndex:(NSInteger)r
{
    return [_rows[(NSUInteger)r] cellAtIndex:c];
}
- (NSGridCell *)cellForView:(NSView *)view
{
    for (NSView *v = view; v && v != self; v = [v superview])
        for (NSGridRow *r in _rows)
            for (NSGridCell *cell in r->_cells)
                if (cell->_content == v)
                    return cell;
    return nil;
}

- (NSGridRow *)addRowWithViews:(NSArray<NSView *> *)views
{
    return [self insertRowAtIndex:[self numberOfRows] withViews:views];
}
- (NSGridRow *)insertRowAtIndex:(NSInteger)index withViews:(NSArray<NSView *> *)views
{
    while ([_columns count] < [views count])
        [self _appendColumn];
    NSGridRow *row = [[[NSGridRow alloc] init] autorelease];
    row->_grid = self;
    for (NSUInteger c = 0; c < [_columns count]; c++) {
        NSView *v = c < [views count] ? views[c] : nil;
        [row->_cells addObject:new_cell(row, _columns[c], v)];
        if (v && v != [NSGridCell emptyContentView])
            [super addSubview:v];
    }
    [_rows insertObject:row atIndex:(NSUInteger)MAX(0, MIN(index, [self numberOfRows]))];
    [self _relayout];
    return row;
}
- (void)_appendColumn
{
    NSGridColumn *col = [[[NSGridColumn alloc] init] autorelease];
    col->_grid = self;
    [_columns addObject:col];
    for (NSGridRow *r in _rows)
        [r->_cells addObject:new_cell(r, col, nil)];
}
- (void)moveRowAtIndex:(NSInteger)from toIndex:(NSInteger)to
{
    NSGridRow *r = [[_rows[(NSUInteger)from] retain] autorelease];
    [_rows removeObjectAtIndex:(NSUInteger)from];
    [_rows insertObject:r atIndex:(NSUInteger)to];
    [self _relayout];
}
- (void)removeRowAtIndex:(NSInteger)index
{
    NSGridRow *r = _rows[(NSUInteger)index];
    for (NSGridCell *cell in r->_cells)
        if ([cell->_content superview] == self)
            [cell->_content removeFromSuperview];
    r->_grid = nil;
    [_rows removeObjectAtIndex:(NSUInteger)index];
    [self _relayout];
}
- (NSGridColumn *)addColumnWithViews:(NSArray<NSView *> *)views
{
    return [self insertColumnAtIndex:[self numberOfColumns] withViews:views];
}
- (NSGridColumn *)insertColumnAtIndex:(NSInteger)index withViews:(NSArray<NSView *> *)views
{
    while ([_rows count] < [views count]) {
        NSGridRow *row = [[[NSGridRow alloc] init] autorelease];
        row->_grid = self;
        for (NSGridColumn *c in _columns)
            [row->_cells addObject:new_cell(row, c, nil)];
        [_rows addObject:row];
    }
    NSUInteger at = (NSUInteger)MAX(0, MIN(index, [self numberOfColumns]));
    NSGridColumn *col = [[[NSGridColumn alloc] init] autorelease];
    col->_grid = self;
    [_columns insertObject:col atIndex:at];
    for (NSUInteger r = 0; r < [_rows count]; r++) {
        NSView *v = r < [views count] ? views[r] : nil;
        [_rows[r]->_cells insertObject:new_cell(_rows[r], col, v) atIndex:at];
        if (v && v != [NSGridCell emptyContentView])
            [super addSubview:v];
    }
    [self _relayout];
    return col;
}
- (void)moveColumnAtIndex:(NSInteger)from toIndex:(NSInteger)to
{
    NSGridColumn *c = [[_columns[(NSUInteger)from] retain] autorelease];
    [_columns removeObjectAtIndex:(NSUInteger)from];
    [_columns insertObject:c atIndex:(NSUInteger)to];
    for (NSGridRow *r in _rows) {
        NSGridCell *cell = [[r->_cells[(NSUInteger)from] retain] autorelease];
        [r->_cells removeObjectAtIndex:(NSUInteger)from];
        [r->_cells insertObject:cell atIndex:(NSUInteger)to];
    }
    [self _relayout];
}
- (void)removeColumnAtIndex:(NSInteger)index
{
    for (NSGridRow *r in _rows) {
        NSGridCell *cell = r->_cells[(NSUInteger)index];
        if ([cell->_content superview] == self)
            [cell->_content removeFromSuperview];
        [r->_cells removeObjectAtIndex:(NSUInteger)index];
    }
    ((NSGridColumn *)_columns[(NSUInteger)index])->_grid = nil;
    [_columns removeObjectAtIndex:(NSUInteger)index];
    [self _relayout];
}
- (void)mergeCellsInHorizontalRange:(NSRange)h verticalRange:(NSRange)v
{
    if (!h.length || !v.length || NSMaxRange(h) > [_columns count] || NSMaxRange(v) > [_rows count])
        return;
    NSGridCell *head = _rows[v.location]->_cells[h.location];
    head->_head = nil;
    for (NSUInteger r = v.location; r < NSMaxRange(v); r++)
        for (NSUInteger c = h.location; c < NSMaxRange(h); c++) {
            NSGridCell *cell = _rows[r]->_cells[c];
            if (cell == head)
                continue;
            cell->_head = head;
            if (!head->_content && cell->_content)
                head->_content = [cell->_content retain];
        }
    [self _relayout];
}

- (NSGridCellPlacement)xPlacement { return _x; }
- (void)setXPlacement:(NSGridCellPlacement)p
{
    _x = p;
    [self _relayout];
}
- (NSGridCellPlacement)yPlacement { return _y; }
- (void)setYPlacement:(NSGridCellPlacement)p
{
    _y = p;
    [self _relayout];
}
- (NSGridRowAlignment)rowAlignment { return _align; }
- (void)setRowAlignment:(NSGridRowAlignment)a { _align = a; }
- (CGFloat)rowSpacing { return _rowSpacing; }
- (void)setRowSpacing:(CGFloat)s
{
    _rowSpacing = s;
    [self _relayout];
}
- (CGFloat)columnSpacing { return _columnSpacing; }
- (void)setColumnSpacing:(CGFloat)s
{
    _columnSpacing = s;
    [self _relayout];
}

/* ---- layout ---------------------------------------------------------------------------- */

/* The widths of the columns and heights of the rows their content asks for
 * (0 for a hidden one), and the size of the whole grid. */
- (NSSize)_sizesWidths:(CGFloat *)widths heights:(CGFloat *)heights
{
    NSUInteger nr = [_rows count], nc = [_columns count];
    for (NSUInteger c = 0; c < nc; c++)
        widths[c] = 0;
    for (NSUInteger r = 0; r < nr; r++)
        heights[r] = 0;
    for (NSUInteger r = 0; r < nr; r++) {
        NSGridRow *row = _rows[r];
        if (row->_hidden)
            continue;
        for (NSUInteger c = 0; c < nc; c++) {
            NSGridCell *cell = row->_cells[c];
            NSGridColumn *col = _columns[c];
            if (col->_hidden || cell->_head || !cell->_content)
                continue;
            /* a merged cell's size is spread over its range by the ones beside it */
            BOOL merged = NO;
            if (c + 1 < nc && ((NSGridCell *)row->_cells[c + 1])->_head == cell)
                merged = YES;
            if (r + 1 < nr && ((NSGridCell *)_rows[r + 1]->_cells[c])->_head == cell)
                merged = YES;
            NSSize s = size_of(cell->_content);
            if (!merged)
                widths[c] = MAX(widths[c], s.width);
            heights[r] = MAX(heights[r], s.height);
        }
    }
    NSSize total = NSZeroSize;
    int shownColumns = 0, shownRows = 0;
    for (NSUInteger c = 0; c < nc; c++) {
        NSGridColumn *col = _columns[c];
        if (col->_hidden) {
            widths[c] = 0;
            continue;
        }
        if (col->_width < NSGridViewSizeForContent)
            widths[c] = col->_width;
        widths[c] += col->_leading + col->_trailing;
        total.width += widths[c];
        shownColumns++;
    }
    for (NSUInteger r = 0; r < nr; r++) {
        NSGridRow *row = _rows[r];
        if (row->_hidden) {
            heights[r] = 0;
            continue;
        }
        if (row->_height < NSGridViewSizeForContent)
            heights[r] = row->_height;
        heights[r] += row->_top + row->_bottom;
        total.height += heights[r];
        shownRows++;
    }
    if (shownColumns > 1)
        total.width += _columnSpacing * (shownColumns - 1);
    if (shownRows > 1)
        total.height += _rowSpacing * (shownRows - 1);
    return total;
}
- (NSSize)fittingSize
{
    NSUInteger nr = [_rows count], nc = [_columns count];
    CGFloat widths[nc ?: 1], heights[nr ?: 1];
    return [self _sizesWidths:widths heights:heights];
}
- (NSSize)intrinsicContentSize { return [self fittingSize]; }

static NSGridCellPlacement resolved(NSGridCellPlacement a, NSGridCellPlacement b, NSGridCellPlacement c)
{
    return a != NSGridCellPlacementInherited ? a : b != NSGridCellPlacementInherited ? b : c;
}
static char grid_hid_key;   /* a view the grid hid for its hidden row or column */

/* where a view of a length goes in a span */
static void place(NSGridCellPlacement p, CGFloat start, CGFloat span, CGFloat length, CGFloat *outStart,
                  CGFloat *outLength)
{
    if (p == NSGridCellPlacementFill || length > span)
        length = span;
    *outLength = length;
    switch (p) {
    case NSGridCellPlacementTrailing:
        *outStart = start + span - length;
        break;
    case NSGridCellPlacementCenter:
        *outStart = start + floor((span - length) / 2);
        break;
    default:
        *outStart = start;
        break;
    }
}

- (void)_relayout
{
    if (_laying || !_rows)
        return;
    _laying = YES;
    NSUInteger nr = [_rows count], nc = [_columns count];
    CGFloat widths[nc ?: 1], heights[nr ?: 1], xs[nc ?: 1], ys[nr ?: 1];
    NSSize total = [self _sizesWidths:widths heights:heights];
    NSSize bounds = [self bounds].size;
    /* the room left over goes to the last column and row that are shown */
    for (NSInteger c = (NSInteger)nc - 1; c >= 0; c--)
        if (!((NSGridColumn *)_columns[(NSUInteger)c])->_hidden) {
            if (bounds.width > total.width && ((NSGridColumn *)_columns[(NSUInteger)c])->_width >= NSGridViewSizeForContent)
                widths[c] += bounds.width - total.width;
            break;
        }
    for (NSInteger r = (NSInteger)nr - 1; r >= 0; r--)
        if (!_rows[(NSUInteger)r]->_hidden) {
            if (bounds.height > total.height && _rows[(NSUInteger)r]->_height >= NSGridViewSizeForContent)
                heights[r] += bounds.height - total.height;
            break;
        }
    CGFloat x = 0, y = 0;
    for (NSUInteger c = 0; c < nc; c++) {
        xs[c] = x;
        if (!((NSGridColumn *)_columns[c])->_hidden)
            x += widths[c] + _columnSpacing;
    }
    for (NSUInteger r = 0; r < nr; r++) {
        ys[r] = y;
        if (!_rows[r]->_hidden)
            y += heights[r] + _rowSpacing;
    }
    for (NSUInteger r = 0; r < nr; r++) {
        NSGridRow *row = _rows[r];
        for (NSUInteger c = 0; c < nc; c++) {
            NSGridCell *cell = row->_cells[c];
            NSGridColumn *col = _columns[c];
            NSView *v = cell->_content;
            if (!v || cell->_head)
                continue;
            /* a hidden row or column hides its views; one the app hid
             * itself stays hidden when its row shows again (freemac
             * 1.236: Itsycal's agenda hides its video button this way) */
            BOOL hidden = row->_hidden || col->_hidden;
            BOOL ours = objc_getAssociatedObject(v, &grid_hid_key) != nil;
            if (hidden && ![v isHidden]) {
                [v setHidden:YES];
                objc_setAssociatedObject(v, &grid_hid_key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (!hidden && ours) {
                objc_setAssociatedObject(v, &grid_hid_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [v setHidden:NO];
            }
            if (hidden)
                continue;
            /* the cells merged into this one widen and heighten it */
            NSUInteger c2 = c, r2 = r;
            while (c2 + 1 < nc && ((NSGridCell *)row->_cells[c2 + 1])->_head == cell)
                c2++;
            while (r2 + 1 < nr && ((NSGridCell *)_rows[r2 + 1]->_cells[c])->_head == cell)
                r2++;
            CGFloat cx = xs[c] + col->_leading, cy = ys[r] + row->_top;
            CGFloat cw = xs[c2] + widths[c2] - xs[c] - col->_leading - ((NSGridColumn *)_columns[c2])->_trailing;
            CGFloat ch = ys[r2] + heights[r2] - ys[r] - row->_top - _rows[r2]->_bottom;
            NSSize s = size_of(v);
            NSRect f;
            place(resolved(cell->_x, col->_x, _x), cx, cw, s.width, &f.origin.x, &f.size.width);
            place(resolved(cell->_y, row->_y, _y), cy, ch, s.height, &f.origin.y, &f.size.height);
            if (!NSEqualRects([v frame], f))
                [v setFrame:f];
        }
    }
    [self setNeedsDisplay:YES];
    _laying = NO;
}
- (void)layout { [self _relayout]; }
- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self _relayout];
}
/* the views are placed by the grid, not by their autoresizing masks */
- (void)resizeSubviewsWithOldSize:(NSSize)old { [self _relayout]; }
@end
