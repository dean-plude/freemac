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
 * Bindings (Ferry 0.19.0): with its content bound to a tree controller's
 * arrangedObjects, the items are the controller's NSTreeNodes (a node's
 * children are its childNodes, and it can open unless it is a leaf), and
 * a column bound to "arrangedObjects.key" shows each node's represented
 * object's key, writing an edited cell back to it. Binding such a column
 * binds the outline's content, selectionIndexPaths and sortDescriptors to
 * the same controller, unless they are bound already. The selection goes
 * both ways as index paths; a node the controller selects is shown, its
 * parents opened. A click on a column's title sorts the controller.
 *
 * Dragging (freemac 1.220, Ferry 0.44.0), as in a table (NSTableView.m)
 * but with items: the data source's outlineView:pasteboardWriterForItem:
 * or outlineView:writeItems:toPasteboard: puts them on the drag
 * pasteboard. A drop is proposed on an item from the middle of its row,
 * or between items as a parent and child index (from the top quarter of a
 * row, before its item; from the bottom quarter, after it, or first under
 * it when it is open; past the last row, at the end of the top level),
 * for outlineView:validateDrop:proposedItem:proposedChildIndex: to take or
 * change with setDropItem:dropChildIndex:, and outlineView:acceptDrop:
 * item:childIndex: to take. A drop between the children of a closed item
 * is shown on the item.
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
    id _dropItem;                    /* the drop proposed (freemac 1.220), retained */
    NSInteger _dropChildIndex;
    NSTrackingArea *_hoverArea;      /* a source list's headings under the mouse, retained */
    NSInteger _hoverRow;             /* the heading under it, plus one (0: none) */
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
    [_dropItem release];
    [_hoverArea release];
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
/* With bound content, the tree it is bound to: what answers childNodes
 * (a tree controller's arrangedObjects), or an array of items. */
- (BOOL)_hasBoundTree { return ABindingIsBound(self, NSContentBinding); }
- (NSArray *)_boundChildrenOf:(id)item
{
    id kids;
    if (item) {
        kids = [item respondsToSelector:@selector(childNodes)] ? [item childNodes] : nil;
    } else {
        id tree = ABindingModelValue(self, NSContentBinding, NULL);
        kids = [tree respondsToSelector:@selector(childNodes)] ? [tree childNodes] : tree;
    }
    if ([kids isKindOfClass:[NSSet class]])
        kids = [kids allObjects];
    return [kids isKindOfClass:[NSArray class]] ? kids : nil;
}
/* The data source's (or the bound tree's) answers. */
- (NSInteger)_numberOfChildrenOf:(id)item
{
    if ([self _hasBoundTree])
        return (NSInteger)[[self _boundChildrenOf:item] count];
    id ds = [self dataSource];
    return [ds respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)] ? [ds outlineView:self numberOfChildrenOfItem:item]
                                                                                 : 0;
}
- (BOOL)_canAskForChildren
{
    return [self _hasBoundTree] || [[self dataSource] respondsToSelector:@selector(outlineView:child:ofItem:)];
}
- (id)_child:(NSInteger)i of:(id)item
{
    if ([self _hasBoundTree]) {
        NSArray *kids = [self _boundChildrenOf:item];
        return i >= 0 && (NSUInteger)i < [kids count] ? [kids objectAtIndex:(NSUInteger)i] : nil;
    }
    return [[self dataSource] outlineView:self child:i ofItem:item];
}
- (BOOL)_itemIsExpandable:(id)item
{
    if ([self _hasBoundTree]) {
        if ([item respondsToSelector:@selector(isLeaf)])
            return ![item isLeaf];
        return [[self _boundChildrenOf:item] count] > 0;
    }
    id ds = [self dataSource];
    return [ds respondsToSelector:@selector(outlineView:isItemExpandable:)] && [ds outlineView:self isItemExpandable:item];
}
/* Asks the data source for node's children again, keeping what is known
 * (open or not, grandchildren) of the ones it had before. */
- (void)_loadChildrenOf:(AOutlineNode *)node
{
    NSInteger n = [self _numberOfChildrenOf:node->item];
    NSMutableArray *old = node->children;
    NSMutableArray *kids = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)MAX(n, 0)];
    BOOL canAsk = [self _canAskForChildren];
    for (NSInteger i = 0; canAsk && i < n; i++) {
        id item = [self _child:i of:node->item];
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
        c->expandable = [self _itemIsExpandable:item];
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
        BOOL was = n->expandable;
        n->expandable = [self _itemIsExpandable:n->item];
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
/* A source list's headings open and close with a Show or Hide button at
 * their right, there while the mouse is over the heading, as on a Mac. */
static NSDictionary *hide_button_attributes(void)
{
    return @{ NSFontAttributeName : [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
              NSForegroundColorAttributeName : [NSColor secondaryLabelColor] };
}
static CGFloat hide_button_width(void)
{
    NSDictionary *a = hide_button_attributes();
    return ceil(fmax([@"Show" sizeWithAttributes:a].width, [@"Hide" sizeWithAttributes:a].width)) + 4;
}
- (BOOL)_showsHideButtonAtRow:(NSInteger)row
{
    return [self selectionHighlightStyle] == NSTableViewSelectionHighlightStyleSourceList && [self _isGroupRow:row];
}
- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_hoverArea || [self selectionHighlightStyle] != NSTableViewSelectionHighlightStyleSourceList)
        return;
    _hoverArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp |
                     NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_hoverArea];
}
- (void)_setHoverRow:(NSInteger)row
{
    if (row + 1 == _hoverRow)
        return;
    NSInteger old = _hoverRow - 1;
    _hoverRow = row + 1;
    for (NSInteger r = 0; r < 2; r++) {
        NSInteger at = r ? row : old;
        if (at < 0 || at >= [self numberOfRows])
            continue;
        NSTableRowView *rv = [self rowViewAtRow:at makeIfNecessary:NO];
        if (rv)
            [rv setNeedsDisplay:YES];
        else
            [self setNeedsDisplayInRect:[self rectOfRow:at]];
    }
}
- (void)mouseMoved:(NSEvent *)e
{
    if (_hoverArea) {
        NSInteger row = [self rowAtPoint:[self convertPoint:[e locationInWindow] fromView:nil]];
        [self _setHoverRow:[self _showsHideButtonAtRow:row] ? row : -1];
    }
    [super mouseMoved:e];
}
- (void)mouseExited:(NSEvent *)e
{
    if (_hoverArea)
        [self _setHoverRow:-1];
    [super mouseExited:e];
}
- (void)_drawHideButtonIn:(NSRect)r row:(NSInteger)row
{
    if (_hoverRow != row + 1)
        return;
    AOutlineNode *n = [self _nodeAtRow:row];
    NSDictionary *a = hide_button_attributes();
    NSString *title = n->expanded ? @"Hide" : @"Show";
    NSSize s = [title sizeWithAttributes:a];
    [title drawAtPoint:NSMakePoint(NSMaxX(r) - s.width - 2, NSMidY(r) - s.height / 2) withAttributes:a];
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
    if ([self _showsHideButtonAtRow:row]) {
        /* a source list's heading: Show or Hide at its right */
        NSRect rr = [self rectOfRow:row];
        CGFloat w = hide_button_width();
        return NSMakeRect(NSMaxX(rr) - w - 6, rr.origin.y, w, rr.size.height);
    }
    NSRect cell = [self frameOfCellAtColumn:column row:row];
    CGFloat x = cell.origin.x - disclosure_width;
    return NSMakeRect(x, cell.origin.y, disclosure_width, cell.size.height);
}

/* ---- the data source and delegate, by item ---- */

- (id)_objectValueForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    BOOL bound;
    id v = ABindingCellValue(c, row, &bound);
    if (bound)
        return v;
    id ds = [self dataSource];
    AOutlineNode *n = [self _nodeAtRow:row];
    /* bound to a tree controller, a row's value is its node's object (Ferry 0.20.0) */
    if (n && [self _hasBoundTree])
        return [n->item isKindOfClass:[NSTreeNode class]] ? [n->item representedObject] : n->item;
    if (n && [ds respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)])
        return [ds outlineView:self objectValueForTableColumn:c byItem:n->item];
    return nil;
}
- (void)_setObjectValue:(id)v forColumn:(NSTableColumn *)c row:(NSInteger)row
{
    if (ABindingIsBound(c, NSValueBinding)) {
        ABindingSetCellValue(c, row, v);
        return;
    }
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
- (BOOL)_delegateMakesViews
{
    return [[self delegate] respondsToSelector:@selector(outlineView:viewForTableColumn:item:)] ||
           [self _makesViewsFromNib];
}
- (NSView *)_delegateViewForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    id d = [self delegate];
    AOutlineNode *n = [self _nodeAtRow:row];
    if (!n)
        return nil;
    if ([d respondsToSelector:@selector(outlineView:viewForTableColumn:item:)])
        return [d outlineView:self viewForTableColumn:c item:n->item];
    return [self _makesViewsFromNib] ? [self _viewFromNibForColumn:c] : nil;
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
    if (![self _ferryIsBindingUpdate])
        ABindingPush(self, NSSortDescriptorsBinding);
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

/* ---- bindings: the selection as index paths ---- */

- (NSArray *)_selectedIndexPaths
{
    NSMutableArray *paths = [NSMutableArray array];
    for (id item in [self _selectedItems])
        if ([item respondsToSelector:@selector(indexPath)])
            [paths addObject:[item indexPath]];
    return paths;
}
/* The bound selection: each path's node is shown (its parents opened)
 * and selected. */
- (void)_selectIndexPaths:(NSArray *)paths
{
    id tree = ABindingModelValue(self, NSContentBinding, NULL);
    NSMutableArray *items = [NSMutableArray array];
    for (NSIndexPath *p in [paths isKindOfClass:[NSArray class]] ? paths : @[]) {
        id node = [p isKindOfClass:[NSIndexPath class]] && [tree respondsToSelector:@selector(descendantNodeAtIndexPath:)]
                      ? [tree descendantNodeAtIndexPath:p]
                      : nil;
        if (node)
            [items addObject:node];
    }
    [self numberOfRows];
    for (id item in items) {
        NSMutableArray *up = [NSMutableArray array];
        for (id a = [item respondsToSelector:@selector(parentNode)] ? [item parentNode] : nil;
             a && [a respondsToSelector:@selector(parentNode)] && [a parentNode]; a = [a parentNode])
            [up insertObject:a atIndex:0];
        for (id a in up)
            if (![self isItemExpanded:a])
                [self expandItem:a];
    }
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (id item in items) {
        NSInteger r = [self rowForItem:item];
        if (r >= 0)
            [rows addIndex:(NSUInteger)r];
    }
    if (![rows isEqualToIndexSet:[self selectedRowIndexes]])
        [self selectRowIndexes:rows byExtendingSelection:NO];
}
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSSelectionIndexPathsBinding])
        [self _ferryAsBindingUpdate:^{
            [self _selectIndexPaths:value];
        }];
    else
        [super _ferrySetValue:value forBinding:binding];
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSSelectionIndexPathsBinding])
        return [self _selectedIndexPaths];
    return [super _ferryValueForBinding:binding];
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
    if ([self _showsHideButtonAtRow:row]) {
        [self _drawHideButtonIn:r row:row];
        return;
    }
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
    if ([self _showsHideButtonAtRow:row]) {
        [self _drawHideButtonIn:r row:row];
        return;
    }
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

/* ---- dragging items, and drops on them (freemac 1.220, Ferry 0.44.0) ---- */

- (NSArray *)_itemsAtRows:(NSIndexSet *)rows
{
    NSMutableArray *items = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        id item = [self itemAtRow:(NSInteger)r];
        if (item)
            [items addObject:item];
    }];
    return items;
}
- (BOOL)_canDragRows
{
    id ds = [self dataSource];
    return [ds respondsToSelector:@selector(outlineView:pasteboardWriterForItem:)] ||
           [ds respondsToSelector:@selector(outlineView:writeItems:toPasteboard:)];
}
- (BOOL)_putRows:(NSIndexSet *)rows onPasteboard:(NSPasteboard *)pb
{
    id ds = [self dataSource];
    NSArray *items = [self _itemsAtRows:rows];
    if (![items count])
        return NO;
    if ([ds respondsToSelector:@selector(outlineView:pasteboardWriterForItem:)]) {
        NSMutableArray *writers = [NSMutableArray array];
        for (id item in items) {
            id w = [ds outlineView:self pasteboardWriterForItem:item];
            if (w)
                [writers addObject:w];
        }
        if ([writers count]) {
            [pb clearContents];
            return [pb writeObjects:writers];
        }
    }
    if ([ds respondsToSelector:@selector(outlineView:writeItems:toPasteboard:)]) {
        [pb clearContents];
        return [ds outlineView:self writeItems:items toPasteboard:pb];
    }
    return NO;
}
- (void)_dragOfRows:(NSIndexSet *)rows session:(NSDraggingSession *)session willBeginAt:(NSPoint)screenPoint
{
    id ds = [self dataSource];
    if ([ds respondsToSelector:@selector(outlineView:draggingSession:willBeginAtPoint:forItems:)])
        [ds outlineView:self draggingSession:session willBeginAtPoint:screenPoint forItems:[self _itemsAtRows:rows]];
}
- (void)_dragSession:(NSDraggingSession *)session endedAt:(NSPoint)screenPoint operation:(NSDragOperation)op
{
    id ds = [self dataSource];
    if ([ds respondsToSelector:@selector(outlineView:draggingSession:endedAtPoint:operation:)])
        [ds outlineView:self draggingSession:session endedAtPoint:screenPoint operation:op];
}
- (void)_updateDraggingItemsForDrag:(id<NSDraggingInfo>)info
{
    id ds = [self dataSource];
    if ([ds respondsToSelector:@selector(outlineView:updateDraggingItemsForDrag:)])
        [ds outlineView:self updateDraggingItemsForDrag:info];
}
- (void)setDropItem:(id)item dropChildIndex:(NSInteger)index
{
    [item retain];
    [_dropItem release];
    _dropItem = item;
    _dropChildIndex = index;
}
- (void)_proposeDropAt:(NSPoint)p
{
    NSInteger n = [self numberOfRows], r = [self rowAtPoint:p];
    if (r < 0) {
        [self setDropItem:nil dropChildIndex:p.y < 0 && n ? 0 : [self numberOfChildrenOfItem:nil]];
        return;
    }
    id item = [self itemAtRow:r];
    NSRect rr = [self rectOfRow:r];
    CGFloat f = (p.y - NSMinY(rr)) / fmax(rr.size.height, 1);
    if (f < 0.25)
        [self setDropItem:[self parentForItem:item] dropChildIndex:[self childIndexForItem:item]];
    else if (f <= 0.75)
        [self setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
    else if ([self isItemExpanded:item] && [self numberOfChildrenOfItem:item] > 0)
        [self setDropItem:item dropChildIndex:0];
    else
        [self setDropItem:[self parentForItem:item] dropChildIndex:[self childIndexForItem:item] + 1];
}
- (NSDragOperation)_validateDrop:(id<NSDraggingInfo>)info
{
    id ds = [self dataSource];
    if (![ds respondsToSelector:@selector(outlineView:validateDrop:proposedItem:proposedChildIndex:)])
        return NSDragOperationNone;
    id item = [[_dropItem retain] autorelease];
    return [ds outlineView:self validateDrop:info proposedItem:item proposedChildIndex:_dropChildIndex];
}
- (BOOL)_acceptDrop:(id<NSDraggingInfo>)info
{
    id ds = [self dataSource];
    if (![ds respondsToSelector:@selector(outlineView:acceptDrop:item:childIndex:)])
        return NO;
    id item = [[_dropItem retain] autorelease];
    return [ds outlineView:self acceptDrop:info item:item childIndex:_dropChildIndex];
}
- (BOOL)_dropFeedbackRow:(NSInteger *)row operation:(NSTableViewDropOperation *)op indent:(CGFloat *)indent
{
    NSInteger at = _dropItem ? [self rowForItem:_dropItem] : -1;
    *indent = 0;
    if (_dropItem && at < 0)
        return NO;      /* an item out of sight */
    if (_dropChildIndex == NSOutlineViewDropOnItemIndex || (_dropItem && ![self isItemExpanded:_dropItem])) {
        *row = at;
        *op = NSTableViewDropOn;
        return YES;
    }
    NSInteger level = _dropItem ? [self levelForRow:at] : -1;
    *indent = (level + 1) * _indent;
    *op = NSTableViewDropAbove;
    if (_dropChildIndex < [self numberOfChildrenOfItem:_dropItem]) {
        NSInteger r = [self rowForItem:[self child:_dropChildIndex ofItem:_dropItem]];
        if (r >= 0) {
            *row = r;
            return YES;
        }
    }
    /* after the parent's last child, and everything open under it */
    NSInteger r = at + 1, n = [self numberOfRows];
    while (r < n && [self levelForRow:r] > level)
        r++;
    *row = r;
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
