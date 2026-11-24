/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: outline views. Our own code, written from Apple's public
 * API documentation.
 *
 * An NSOutlineView is a table whose rows are a tree of the data source's
 * items. It keeps a node for each item it has asked about (the item, its
 * parent, its depth, whether it is open, its children once asked for) and
 * shows the open part of the tree as rows, top to bottom. Items are told
 * apart by identity first and then by isEqual:. The outline column shows a
 * disclosure chevron, drawn here, before each item that can open, and its
 * cells are indented by indentationPerLevel for each level.
 *
 * Opening and closing ask the delegate (outlineView:shouldExpandItem:,
 * outlineView:shouldCollapseItem:) and post the will/did expand and
 * collapse notifications, with the item under "NSObject"; the delegate is
 * signed up for them, as on a Mac. The selection follows its items when
 * rows open and close; items hidden by a close are deselected.
 *
 * Cells are edited in place as in a table (see NSTableView.m), with the
 * new value going to outlineView:setObjectValue:forTableColumn:byItem:
 * and the delegate's outlineView:shouldEditTableColumn:item: asked first.
 *
 * Nibs: "NSOutlineViewIndentationPerLevelKey" and
 * "NSOutlineViewOutlineTableColumnKey". */
#import "AInternal.h"

NSNotificationName const NSOutlineViewSelectionDidChangeNotification = @"NSOutlineViewSelectionDidChangeNotification";
NSNotificationName const NSOutlineViewSelectionIsChangingNotification = @"NSOutlineViewSelectionIsChangingNotification";
NSNotificationName const NSOutlineViewColumnDidMoveNotification = @"NSOutlineViewColumnDidMoveNotification";
NSNotificationName const NSOutlineViewColumnDidResizeNotification = @"NSOutlineViewColumnDidResizeNotification";
NSNotificationName const NSOutlineViewItemWillExpandNotification = @"NSOutlineViewItemWillExpandNotification";
NSNotificationName const NSOutlineViewItemDidExpandNotification = @"NSOutlineViewItemDidExpandNotification";
NSNotificationName const NSOutlineViewItemWillCollapseNotification = @"NSOutlineViewItemWillCollapseNotification";
NSNotificationName const NSOutlineViewItemDidCollapseNotification = @"NSOutlineViewItemDidCollapseNotification";
NSUserInterfaceItemIdentifier const NSOutlineViewDisclosureButtonKey = @"NSOutlineViewDisclosureButtonKey";
NSUserInterfaceItemIdentifier const NSOutlineViewShowHideButtonKey = @"NSOutlineViewShowHideButtonKey";

static const CGFloat disclosure_width = 16;

/* One item the outline knows of. */
@interface AOutlineNode : NSObject {
@public
    id item;
    AOutlineNode *parent;     /* not retained */
    NSInteger level;
    NSMutableArray *children; /* nil until asked for */
    BOOL expandable, expanded;
}
@end
@implementation AOutlineNode
- (void)dealloc
{
    [item release];
    [children release];
    [super dealloc];
}
@end

@implementation NSOutlineView {
    NSTableColumn *_outlineColumn;   /* not retained: the table holds its columns */
    CGFloat _indent;
    BOOL _markerFollowsCell, _autoresizesOutline, _autosaveExpanded, _strong;
    AOutlineNode *_root;
    NSMutableArray *_rowNodes;       /* the open part of the tree, as rows */
    BOOL _reloadTree;
}

- (void)_setUpOutline
{
    _indent = 16;
    _autoresizesOutline = _strong = YES;
    _root = [[AOutlineNode alloc] init];
    _root->level = -1;
    _root->expandable = _root->expanded = YES;
    _rowNodes = [[NSMutableArray alloc] init];
    _reloadTree = YES;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUpOutline];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    if (!_root)
        [self _setUpOutline];
    if ([coder containsValueForKey:@"NSOutlineViewIndentationPerLevelKey"])
        _indent = fmax([coder decodeDoubleForKey:@"NSOutlineViewIndentationPerLevelKey"], 0);
    id column = [coder containsValueForKey:@"NSOutlineViewOutlineTableColumnKey"]
                    ? [coder decodeObjectForKey:@"NSOutlineViewOutlineTableColumnKey"]
                    : nil;
    if ([column isKindOfClass:[NSTableColumn class]])
        _outlineColumn = column;
    return self;
}
- (void)dealloc
{
    [_root release];
    [_rowNodes release];
    [super dealloc];
}

/* The table's own setup asks for the rows before ours has run. */
- (NSInteger)_countRows
{
    if (!_root)
        return 0;
    if (_reloadTree) {
        _reloadTree = NO;
        [self _loadChildrenOf:_root];
    }
    [_rowNodes removeAllObjects];
    [self _addRowsUnder:_root];
    return (NSInteger)[_rowNodes count];
}

/* ---- settings ---- */

- (NSTableColumn *)outlineTableColumn
{
    if (_outlineColumn && [[self tableColumns] indexOfObjectIdenticalTo:_outlineColumn] != NSNotFound)
        return _outlineColumn;
    return [[self tableColumns] firstObject];
}
- (void)setOutlineTableColumn:(NSTableColumn *)c
{
    _outlineColumn = c;
    [self tile];
}
- (CGFloat)indentationPerLevel { return _indent; }
- (void)setIndentationPerLevel:(CGFloat)v
{
    _indent = fmax(v, 0);
    [self tile];
}
- (BOOL)indentationMarkerFollowsCell { return _markerFollowsCell; }
- (void)setIndentationMarkerFollowsCell:(BOOL)f { _markerFollowsCell = f; }
- (BOOL)autoresizesOutlineColumn { return _autoresizesOutline; }
- (void)setAutoresizesOutlineColumn:(BOOL)f { _autoresizesOutline = f; }
- (BOOL)autosaveExpandedItems { return _autosaveExpanded; }
- (void)setAutosaveExpandedItems:(BOOL)f { _autosaveExpanded = f; }
- (BOOL)stronglyReferencesItems { return _strong; }
- (void)setStronglyReferencesItems:(BOOL)f { _strong = f; }

/* The delegate hears the expand and collapse notifications too. */
- (void)setDelegate:(id)d
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSString *names[] = {NSOutlineViewItemWillExpandNotification, NSOutlineViewItemDidExpandNotification,
                         NSOutlineViewItemWillCollapseNotification, NSOutlineViewItemDidCollapseNotification};
    SEL sels[] = {@selector(outlineViewItemWillExpand:), @selector(outlineViewItemDidExpand:),
                  @selector(outlineViewItemWillCollapse:), @selector(outlineViewItemDidCollapse:)};
    id old = [self delegate];
    for (int i = 0; i < 4 && old; i++)
        [nc removeObserver:old name:names[i] object:self];
    [super setDelegate:d];
    for (int i = 0; i < 4; i++)
        if ([d respondsToSelector:sels[i]])
            [nc addObserver:d selector:sels[i] name:names[i] object:self];
}

/* ---- the tree ---- */

static BOOL same_item(id a, id b) { return a == b || (a && b && [a isEqual:b]); }

- (AOutlineNode *)_nodeForItem:(id)item under:(AOutlineNode *)node identical:(BOOL)identical
{
    for (AOutlineNode *c in node->children) {
        if (identical ? c->item == item : same_item(c->item, item))
            return c;
        AOutlineNode *found = [self _nodeForItem:item under:c identical:identical];
        if (found)
            return found;
    }
    return nil;
}
- (AOutlineNode *)_nodeForItem:(id)item
{
    if (!item)
        return _root;
    /* the rows first: they are what is usually asked about */
    for (AOutlineNode *n in _rowNodes)
        if (n->item == item)
            return n;
    return [self _nodeForItem:item under:_root identical:YES] ?: [self _nodeForItem:item under:_root identical:NO];
}
/* Asks the data source for node's children again, keeping what is known
 * (open or not, grandchildren) of the ones it had before. */
- (void)_loadChildrenOf:(AOutlineNode *)node
{
    id ds = [self dataSource];
    NSInteger n = [ds respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]
                      ? [ds outlineView:self numberOfChildrenOfItem:node->item]
                      : 0;
    NSMutableArray *old = node->children;
    NSMutableArray *kids = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)MAX(n, 0)];
    BOOL canAsk = [ds respondsToSelector:@selector(outlineView:child:ofItem:)];
    for (NSInteger i = 0; canAsk && i < n; i++) {
        id item = [ds outlineView:self child:i ofItem:node->item];
        AOutlineNode *c = nil;
        for (AOutlineNode *o in old)
            if (o->item == item) {
                c = o;
                break;
            }
        if (!c)
            for (AOutlineNode *o in old)
                if (same_item(o->item, item)) {
                    c = o;
                    break;
                }
        if (c) {
            [c retain];
            [old removeObjectIdenticalTo:c];
            if (c->item != item) {
                [c->item release];
                c->item = [item retain];
            }
        } else {
            c = [[AOutlineNode alloc] init];
            c->item = [item retain];
        }
        c->parent = node;
        c->level = node->level + 1;
        c->expandable = [ds respondsToSelector:@selector(outlineView:isItemExpandable:)] &&
                        [ds outlineView:self isItemExpandable:item];
        if (!c->expandable) {
            c->expanded = NO;
            [c->children release];
            c->children = nil;
        } else if (c->expanded || c->children) {
            [self _loadChildrenOf:c];
        }
        [kids addObject:c];
        [c release];
    }
    [old release];
    node->children = kids;
}
- (void)_addRowsUnder:(AOutlineNode *)node
{
    for (AOutlineNode *c in node->children) {
        [_rowNodes addObject:c];
        if (c->expandable && c->expanded) {
            if (!c->children)
                [self _loadChildrenOf:c];
            [self _addRowsUnder:c];
        }
    }
}
- (AOutlineNode *)_nodeAtRow:(NSInteger)row
{
    [self numberOfRows];
    return row >= 0 && row < (NSInteger)[_rowNodes count] ? [_rowNodes objectAtIndex:(NSUInteger)row] : nil;
}

- (void)reloadData
{
    _reloadTree = YES;
    [super reloadData];
}

/* Works the rows out again and moves the selection with its items. Items
 * no longer shown are deselected, which is a change of selection. */
- (void)_rowsChangedKeeping:(NSArray *)items
{
    NSInteger lead = [self selectedRow];
    id leadItem = lead >= 0 ? [self itemAtRow:lead] : nil;
    [self _reloadRowsQuietly];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (id item in items) {
        NSInteger r = [self rowForItem:item];
        if (r >= 0)
            [rows addIndex:(NSUInteger)r];
    }
    NSInteger newLead = leadItem ? [self rowForItem:leadItem] : -1;
    if (newLead >= 0)
        [self _setAnchor:newLead];
    [self _setSelection:rows notify:[rows count] != [items count]];
    [self setNeedsDisplay:YES];
}
- (NSArray *)_selectedItems
{
    NSMutableArray *items = [NSMutableArray array];
    [[self selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        id item = [self itemAtRow:(NSInteger)r];
        if (item)
            [items addObject:item];
    }];
    return items;
}

/* ---- the outline's API ---- */

- (BOOL)isExpandable:(id)item
{
    AOutlineNode *n = [self _nodeForItem:item];
    return n && n->expandable;
}
- (NSInteger)numberOfChildrenOfItem:(id)item
{
    AOutlineNode *n = [self _nodeForItem:item];
    if (!n || !n->expandable)
        return 0;
    if (!n->children)
        [self _loadChildrenOf:n];
    return (NSInteger)[n->children count];
}
- (id)child:(NSInteger)index ofItem:(id)item
{
    AOutlineNode *n = [self _nodeForItem:item];
    if (n && n->expandable && !n->children)
        [self _loadChildrenOf:n];
    return n && index >= 0 && index < (NSInteger)[n->children count] ? ((AOutlineNode *)[n->children objectAtIndex:(NSUInteger)index])->item : nil;
}
- (BOOL)isItemExpanded:(id)item
{
    AOutlineNode *n = [self _nodeForItem:item];
    return n && (n == _root || (n->expandable && n->expanded));
}
- (id)itemAtRow:(NSInteger)row
{
    AOutlineNode *n = [self _nodeAtRow:row];
    return n ? n->item : nil;
}
- (NSInteger)rowForItem:(id)item
{
    [self numberOfRows];
    NSUInteger i = [_rowNodes indexOfObjectPassingTest:^BOOL(id n, NSUInteger idx, BOOL *stop) {
        return ((AOutlineNode *)n)->item == item;
    }];
    if (i == NSNotFound)
        i = [_rowNodes indexOfObjectPassingTest:^BOOL(id n, NSUInteger idx, BOOL *stop) {
            return same_item(((AOutlineNode *)n)->item, item);
        }];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (NSInteger)levelForItem:(id)item
{
    if (!item)
        return -1;
    AOutlineNode *n = [self _nodeForItem:item];
    return n ? n->level : -1;
}
- (NSInteger)levelForRow:(NSInteger)row
{
    AOutlineNode *n = [self _nodeAtRow:row];
    return n ? n->level : -1;
}
- (id)parentForItem:(id)item
{
    AOutlineNode *n = item ? [self _nodeForItem:item] : nil;
    return n && n->parent ? n->parent->item : nil;
}
- (NSInteger)childIndexForItem:(id)item
{
    AOutlineNode *n = item ? [self _nodeForItem:item] : nil;
    if (!n || !n->parent)
        return -1;
    NSUInteger i = [n->parent->children indexOfObjectIdenticalTo:n];
    return i == NSNotFound ? -1 : (NSInteger)i;
}

- (BOOL)_shouldExpand:(AOutlineNode *)n
{
    id d = [self delegate];
    return ![d respondsToSelector:@selector(outlineView:shouldExpandItem:)] || [d outlineView:self shouldExpandItem:n->item];
}
- (BOOL)_shouldCollapse:(AOutlineNode *)n
{
    id d = [self delegate];
    return ![d respondsToSelector:@selector(outlineView:shouldCollapseItem:)] ||
           [d outlineView:self shouldCollapseItem:n->item];
}
- (void)_postItem:(NSNotificationName)name item:(id)item
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name
                                                        object:self
                                                      userInfo:item ? @{@"NSObject" : item} : nil];
}
/* Opens n (and, with all, everything under it). Returns whether anything opened. */
- (BOOL)_expand:(AOutlineNode *)n children:(BOOL)all
{
    BOOL changed = NO;
    if (n != _root && n->expandable && !n->expanded) {
        if (![self _shouldExpand:n])
            return NO;
        [self _postItem:NSOutlineViewItemWillExpandNotification item:n->item];
        n->expanded = YES;
        if (!n->children)
            [self _loadChildrenOf:n];
        [self _postItem:NSOutlineViewItemDidExpandNotification item:n->item];
        changed = YES;
    }
    if (all && n->expandable && n->expanded) {
        if (!n->children)
            [self _loadChildrenOf:n];
        for (AOutlineNode *c in [[n->children copy] autorelease])
            changed |= [self _expand:c children:YES];
    }
    return changed;
}
- (BOOL)_collapse:(AOutlineNode *)n children:(BOOL)all
{
    BOOL changed = NO;
    if (all)
        for (AOutlineNode *c in [[n->children copy] autorelease])
            changed |= [self _collapse:c children:YES];
    if (n != _root && n->expandable && n->expanded) {
        if (![self _shouldCollapse:n])
            return changed;
        [self _postItem:NSOutlineViewItemWillCollapseNotification item:n->item];
        n->expanded = NO;
        [self _postItem:NSOutlineViewItemDidCollapseNotification item:n->item];
        changed = YES;
    }
    return changed;
}
- (void)expandItem:(id)item expandChildren:(BOOL)all
{
    [self numberOfRows];
    AOutlineNode *n = [self _nodeForItem:item];
    if (!n)
        return;
    NSArray *selected = [self _selectedItems];
    if ([self _expand:n children:all || n == _root])
        [self _rowsChangedKeeping:selected];
}
- (void)expandItem:(id)item { [self expandItem:item expandChildren:NO]; }
- (void)collapseItem:(id)item collapseChildren:(BOOL)all
{
    [self numberOfRows];
    AOutlineNode *n = [self _nodeForItem:item];
    if (!n)
        return;
    NSArray *selected = [self _selectedItems];
    if ([self _collapse:n children:all || n == _root])
        [self _rowsChangedKeeping:selected];
}
- (void)collapseItem:(id)item { [self collapseItem:item collapseChildren:NO]; }
- (void)reloadItem:(id)item reloadChildren:(BOOL)children
{
    [self numberOfRows];
    AOutlineNode *n = [self _nodeForItem:item];
    if (!n)
        return;
    NSArray *selected = [self _selectedItems];
    if (n == _root || children) {
        [self _loadChildrenOf:n];
    } else {
        id ds = [self dataSource];
        BOOL was = n->expandable;
        n->expandable = [ds respondsToSelector:@selector(outlineView:isItemExpandable:)] &&
                        [ds outlineView:self isItemExpandable:n->item];
        if (!n->expandable)
            n->expanded = NO;
        if (was == n->expandable) {
            NSInteger r = [self rowForItem:n->item];
            if (r >= 0)
                [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r]
                                columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)[self numberOfColumns])]];
            return;
        }
    }
    [self _rowsChangedKeeping:selected];
}
- (void)reloadItem:(id)item { [self reloadItem:item reloadChildren:NO]; }
- (void)insertItemsAtIndexes:(NSIndexSet *)indexes inParent:(id)parent withAnimation:(NSTableViewAnimationOptions)options
{
    [self reloadItem:parent reloadChildren:YES];
}
- (void)removeItemsAtIndexes:(NSIndexSet *)indexes inParent:(id)parent withAnimation:(NSTableViewAnimationOptions)options
{
    [self reloadItem:parent reloadChildren:YES];
}
- (void)moveItemAtIndex:(NSInteger)from inParent:(id)oldParent toIndex:(NSInteger)to inParent:(id)newParent
{
    [self reloadItem:oldParent reloadChildren:YES];
    if (!same_item(oldParent, newParent))
        [self reloadItem:newParent reloadChildren:YES];
}

/* ---- geometry: the outline column is indented ---- */

- (BOOL)_isOutlineColumn:(NSInteger)column
{
    NSArray *cols = [self tableColumns];
    return column >= 0 && column < (NSInteger)[cols count] && [cols objectAtIndex:(NSUInteger)column] == [self outlineTableColumn];
}
- (CGFloat)_indentationForRow:(NSInteger)row column:(NSInteger)column
{
    if (![self _isOutlineColumn:column])
        return 0;
    AOutlineNode *n = [self _nodeAtRow:row];
    if (!n || [self _isGroupRow:row])
        return 0;
    return disclosure_width + n->level * _indent;
}
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row
{
    AOutlineNode *n = [self _nodeAtRow:row];
    NSInteger column = (NSInteger)[[self tableColumns] indexOfObjectIdenticalTo:[self outlineTableColumn]];
    if (!n || !n->expandable || column < 0 || column == (NSInteger)NSNotFound)
        return NSZeroRect;
    id d = [self delegate];
    if ([d respondsToSelector:@selector(outlineView:shouldShowOutlineCellForItem:)] &&
        ![d outlineView:self shouldShowOutlineCellForItem:n->item])
        return NSZeroRect;
    NSRect cell = [self frameOfCellAtColumn:column row:row];
    CGFloat x = cell.origin.x - disclosure_width;
    return NSMakeRect(x, cell.origin.y, disclosure_width, cell.size.height);
}

/* ---- the data source and delegate, by item ---- */

- (id)_objectValueForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id ds = [self dataSource];
    AOutlineNode *n = [self _nodeAtRow:row];
    if (n && [ds respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)])
        return [ds outlineView:self objectValueForTableColumn:c byItem:n->item];
    return nil;
}
- (void)_setObjectValue:(id)v forColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id ds = [self dataSource];
    AOutlineNode *n = [self _nodeAtRow:row];
    if (n && [ds respondsToSelector:@selector(outlineView:setObjectValue:forTableColumn:byItem:)])
        [ds outlineView:self setObjectValue:v forTableColumn:c byItem:n->item];
}
- (BOOL)_dataSourceTakesValues
{
    return [[self dataSource] respondsToSelector:@selector(outlineView:setObjectValue:forTableColumn:byItem:)];
}
- (BOOL)_shouldEditColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    if (!n)
        return NO;
    return ![d respondsToSelector:@selector(outlineView:shouldEditTableColumn:item:)] ||
           [d outlineView:self shouldEditTableColumn:c item:n->item];
}
- (BOOL)_delegateMakesViews { return [[self delegate] respondsToSelector:@selector(outlineView:viewForTableColumn:item:)]; }
- (NSView *)_delegateViewForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    return n && [d respondsToSelector:@selector(outlineView:viewForTableColumn:item:)]
               ? [d outlineView:self viewForTableColumn:c item:n->item]
               : nil;
}
- (NSTableRowView *)_delegateRowViewForRow:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    return n && [d respondsToSelector:@selector(outlineView:rowViewForItem:)] ? [d outlineView:self rowViewForItem:n->item]
                                                                            : nil;
}
- (void)_didAddRowView:(NSTableRowView *)v row:(NSInteger)row
{
    if ([[self delegate] respondsToSelector:@selector(outlineView:didAddRowView:forRow:)])
        [[self delegate] outlineView:self didAddRowView:v forRow:row];
}
- (void)_didRemoveRowView:(NSTableRowView *)v row:(NSInteger)row
{
    if ([[self delegate] respondsToSelector:@selector(outlineView:didRemoveRowView:forRow:)])
        [[self delegate] outlineView:self didRemoveRowView:v forRow:row];
}
- (NSCell *)_delegateCellForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    return n && [d respondsToSelector:@selector(outlineView:dataCellForTableColumn:item:)]
               ? [d outlineView:self dataCellForTableColumn:c item:n->item]
               : nil;
}
- (void)_willDisplayCell:(NSCell *)cell column:(NSTableColumn *)c row:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    if (n && [d respondsToSelector:@selector(outlineView:willDisplayCell:forTableColumn:item:)])
        [d outlineView:self willDisplayCell:cell forTableColumn:c item:n->item];
}
- (BOOL)_delegateHasRowHeights { return [[self delegate] respondsToSelector:@selector(outlineView:heightOfRowByItem:)]; }
- (CGFloat)_delegateHeightOfRow:(NSInteger)row
{
    AOutlineNode *n = row >= 0 && row < (NSInteger)[_rowNodes count] ? [_rowNodes objectAtIndex:(NSUInteger)row] : nil;
    return n ? [[self delegate] outlineView:self heightOfRowByItem:n->item] : 0;
}
- (BOOL)_isGroupRow:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = row >= 0 && row < (NSInteger)[_rowNodes count] ? [_rowNodes objectAtIndex:(NSUInteger)row] : nil;
    return n && [d respondsToSelector:@selector(outlineView:isGroupItem:)] && [d outlineView:self isGroupItem:n->item];
}
- (BOOL)_selectionShouldChange
{
    id d = [self delegate];
    return ![d respondsToSelector:@selector(selectionShouldChangeInOutlineView:)] || [d selectionShouldChangeInOutlineView:self];
}
- (BOOL)_shouldSelectRow:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    return n && (![d respondsToSelector:@selector(outlineView:shouldSelectItem:)] || [d outlineView:self shouldSelectItem:n->item]);
}
- (NSNotificationName)_selectionDidChangeName { return NSOutlineViewSelectionDidChangeNotification; }
- (SEL)_selectionDidChangeSelector { return @selector(outlineViewSelectionDidChange:); }
- (NSNotificationName)_columnDidResizeName { return NSOutlineViewColumnDidResizeNotification; }
- (SEL)_columnDidResizeSelector { return @selector(outlineViewColumnDidResize:); }
- (void)_sortDescriptorsDidChange:(NSArray *)old
{
    id ds = [self dataSource];
    if ([ds respondsToSelector:@selector(outlineView:sortDescriptorsDidChange:)])
        [ds outlineView:self sortDescriptorsDidChange:old];
}
- (void)_mouseDownInHeaderOfColumn:(NSTableColumn *)c
{
    if ([[self delegate] respondsToSelector:@selector(outlineView:mouseDownInHeaderOfTableColumn:)])
        [[self delegate] outlineView:self mouseDownInHeaderOfTableColumn:c];
}
- (void)_didClickColumn:(NSTableColumn *)c
{
    if ([[self delegate] respondsToSelector:@selector(outlineView:didClickTableColumn:)])
        [[self delegate] outlineView:self didClickTableColumn:c];
}

/* ---- the disclosure chevrons ---- */

- (NSColor *)_chevronColorForRow:(NSInteger)row
{
    return [self isRowSelected:row] && [self _isEmphasized] && [self selectionHighlightStyle] != NSTableViewSelectionHighlightStyleNone
               ? [NSColor alternateSelectedControlTextColor]
               : [NSColor secondaryLabelColor];
}
- (void)_drawDecorationsForRow:(NSInteger)row
{
    NSRect r = [self frameOfOutlineCellAtRow:row];
    if (NSIsEmptyRect(r))
        return;
    AOutlineNode *n = [self _nodeAtRow:row];
    ATableDrawChevron(r, n->expanded, [self _chevronColorForRow:row], YES);
}
- (void)_drawDecorationsInRowView:(NSTableRowView *)view
{
    NSInteger row = [self _rowForRowView:view];
    NSRect r = [self frameOfOutlineCellAtRow:row];
    if (NSIsEmptyRect(r))
        return;
    r.origin.y -= [self rectOfRow:row].origin.y;
    AOutlineNode *n = [self _nodeAtRow:row];
    ATableDrawChevron(r, n->expanded, [self _chevronColorForRow:row], [view isFlipped]);
}
/* A click on a chevron opens or closes its item (with option, everything
 * under it too). */
- (BOOL)_handleMouseDown:(NSEvent *)e row:(NSInteger)row column:(NSInteger)column point:(NSPoint)p
{
    NSRect r = [self frameOfOutlineCellAtRow:row];
    if (NSIsEmptyRect(r) || !NSMouseInRect(p, NSInsetRect(r, -2, 0), YES))
        return NO;
    AOutlineNode *n = [self _nodeAtRow:row];
    BOOL all = ([e modifierFlags] & NSEventModifierFlagOption) != 0;
    if (n->expanded)
        [self collapseItem:n->item collapseChildren:all];
    else
        [self expandItem:n->item expandChildren:all];
    return YES;
}

/* ---- keys: right opens, left closes (or goes to the parent) ---- */

- (void)moveRight:(id)sender
{
    NSIndexSet *rows = [self selectedRowIndexes];
    NSMutableArray *items = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        AOutlineNode *n = [self _nodeAtRow:(NSInteger)r];
        if (n && n->expandable && !n->expanded)
            [items addObject:n->item];
    }];
    for (id item in items)
        [self expandItem:item];
}
- (void)moveLeft:(id)sender
{
    NSIndexSet *rows = [self selectedRowIndexes];
    if ([rows count] == 1) {
        AOutlineNode *n = [self _nodeAtRow:(NSInteger)[rows firstIndex]];
        if (n && !(n->expandable && n->expanded) && n->parent && n->parent != _root) {
            NSInteger r = [self rowForItem:n->parent->item];
            if (r >= 0 && [self _shouldSelectRow:r] && [self _selectionShouldChange]) {
                [self _setAnchor:r];
                [self _setSelection:[NSIndexSet indexSetWithIndex:(NSUInteger)r] notify:YES];
                [self scrollRowToVisible:r];
            }
            return;
        }
    }
    NSMutableArray *items = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        AOutlineNode *n = [self _nodeAtRow:(NSInteger)r];
        if (n && n->expandable && n->expanded)
            [items addObject:n->item];
    }];
    for (id item in items)
        [self collapseItem:item];
}
@end
