/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSTreeNode and NSTreeController (Ferry 0.19.0), as Apple's public
 * documentation describes them. No Apple code was used.
 *
 * A tree node stands for one object (its representedObject) and holds its
 * child nodes; its indexPath is where it is under its root. mutableChildNodes
 * changes the children through key-value coding, so observers of childNodes
 * hear of each change, and a node put in or taken out gets its parentNode
 * set. sortWithSortDescriptors:recursively: compares the nodes themselves
 * (key paths such as "representedObject.name").
 *
 * The tree controller's content is an array of objects (or a set, or one
 * object), given with setContent: or by the contentArray, contentSet or
 * contentObject binding. Each object's children are the array (or set) at
 * childrenKeyPath. A node is a leaf when its leafKeyPath says so; without
 * one, when its countKeyPath's count is 0; without either, when it has no
 * children. arrangedObjects is a proxy answering childNodes and
 * descendantNodeAtIndexPath:: a tree of NSTreeNode, each level sorted by
 * sortDescriptors. The nodes are kept from one arrangement to the next for
 * the same objects, so an outline view keeps them open. The controller
 * observes every object's children (and count and leaf) key paths and
 * arranges the tree again when they change.
 *
 * The selection is a list of index paths (selectionIndexPaths), and
 * "selection.someKey" reads and writes the selected objects as an array
 * controller's does. preservesSelection keeps the selected objects
 * selected through a new arrangement; avoidsEmptySelection selects the
 * first node when content arrives, and the node now where a removed one
 * was (or its parent) when the selected ones go.
 *
 * Adding and inserting go through the parent object's children key path
 * (mutableArrayValueForKeyPath: or mutableSetValueForKeyPath:, so its owner
 * hears of it; a dictionary's children are replaced by a changed copy),
 * or, at the top, through the bound content array or set. add: adds a new
 * object after the selected node's last sibling (at the top with no
 * selection), insert: puts one where the selected node is, addChild: after
 * its last child and insertChild: before its first; remove: removes the
 * selected objects. These actions are carried out on the run loop's next
 * turn, as Apple documents. With selectsInsertedObjects new objects
 * become the selection. Inserted objects take their sorted place at once. */
#import "AInternal.h"

NSString *const NSSelectionIndexPathsBinding = @"selectionIndexPaths";

static char tree_context;

static BOOL truth(id v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : v != nil; }
static NSNumber *ptr(id o) { return @((uintptr_t)o); }

/* ---- NSTreeNode ------------------------------------------------------------------- */

@interface NSTreeNode () {
@public
    id _object;
    NSTreeNode *_parent;            /* not retained */
    NSMutableArray *_children;
    signed char _leaf;              /* -1: by its children; 0 or 1: as its tree controller says */
}
@end

@implementation NSTreeNode
+ (instancetype)treeNodeWithRepresentedObject:(id)modelObject
{
    return [[[self alloc] initWithRepresentedObject:modelObject] autorelease];
}
- (instancetype)init { return [self initWithRepresentedObject:nil]; }
- (instancetype)initWithRepresentedObject:(id)modelObject
{
    if ((self = [super init])) {
        _object = [modelObject retain];
        _children = [[NSMutableArray alloc] init];
        _leaf = -1;
    }
    return self;
}
- (void)dealloc
{
    for (NSTreeNode *c in _children)
        if (c->_parent == self)
            c->_parent = nil;
    [_children release];
    [_object release];
    [super dealloc];
}
- (id)representedObject { return _object; }
- (NSTreeNode *)parentNode { return _parent; }
- (BOOL)isLeaf { return _leaf >= 0 ? _leaf : [_children count] == 0; }
- (NSArray *)childNodes { return [[_children copy] autorelease]; }
- (NSMutableArray *)mutableChildNodes { return [self mutableArrayValueForKey:@"childNodes"]; }
- (NSUInteger)countOfChildNodes { return [_children count]; }
- (id)objectInChildNodesAtIndex:(NSUInteger)i { return [_children objectAtIndex:i]; }
- (void)insertObject:(NSTreeNode *)node inChildNodesAtIndex:(NSUInteger)i
{
    [node retain];
    if (node->_parent && node->_parent != self) {
        NSUInteger at = [node->_parent->_children indexOfObjectIdenticalTo:node];
        if (at != NSNotFound)
            [[node->_parent mutableChildNodes] removeObjectAtIndex:at];
    }
    [_children insertObject:node atIndex:i];
    node->_parent = self;
    [node release];
}
- (void)removeObjectFromChildNodesAtIndex:(NSUInteger)i
{
    NSTreeNode *node = [_children objectAtIndex:i];
    if (node->_parent == self)
        node->_parent = nil;
    [_children removeObjectAtIndex:i];
}
- (void)replaceObjectInChildNodesAtIndex:(NSUInteger)i withObject:(NSTreeNode *)node
{
    [self removeObjectFromChildNodesAtIndex:i];
    [self insertObject:node inChildNodesAtIndex:i];
}
- (NSIndexPath *)indexPath
{
    NSUInteger depth = 0;
    for (NSTreeNode *n = self; n->_parent; n = n->_parent)
        depth++;
    NSUInteger *buf = malloc((depth ? depth : 1) * sizeof(NSUInteger));
    NSUInteger i = depth;
    for (NSTreeNode *n = self; n->_parent; n = n->_parent)
        buf[--i] = [n->_parent->_children indexOfObjectIdenticalTo:n];
    NSIndexPath *p = [NSIndexPath indexPathWithIndexes:buf length:depth];
    free(buf);
    return p;
}
- (NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)path
{
    NSTreeNode *n = self;
    for (NSUInteger i = 0; n && i < [path length]; i++) {
        NSUInteger at = [path indexAtPosition:i];
        n = at < [n->_children count] ? [n->_children objectAtIndex:at] : nil;
    }
    return n;
}
- (void)sortWithSortDescriptors:(NSArray *)descriptors recursively:(BOOL)recursively
{
    if ([descriptors count]) {
        [self willChangeValueForKey:@"childNodes"];
        [_children sortUsingDescriptors:descriptors];
        [self didChangeValueForKey:@"childNodes"];
    }
    if (recursively)
        for (NSTreeNode *c in _children)
            [c sortWithSortDescriptors:descriptors recursively:YES];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: %@, %lu children>", [self class], self, _object,
                                      (unsigned long)[_children count]];
}
@end

/* ---- arrangedObjects ---------------------------------------------------------------- */

/* The tree's top: childNodes are the top-level nodes. Keys observed on it
 * are observed on every object of the tree (so a column bound to
 * "arrangedObjects.name" is redrawn when a name changes). */
@interface ATreeArranged : AKeyProxy {
@public
    NSTreeController *controller;   /* not retained: it owns us */
}
@end

@interface NSTreeController (FerryTree)
- (NSTreeNode *)_root;
- (NSArray *)_allObjects;
@end

@implementation ATreeArranged
- (NSArray *)_sources { return controller ? [controller _allObjects] : [NSArray array]; }
- (NSArray *)childNodes { return controller ? [[controller _root] childNodes] : [NSArray array]; }
- (NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)path
{
    return [path length] ? [[controller _root] descendantNodeAtIndexPath:path] : nil;
}
- (BOOL)_ferryIsKeyValueProxy { return YES; }
/* anything else: as an array of the top-level objects would answer */
- (id)valueForUndefinedKey:(NSString *)key
{
    return [[[[controller _root] childNodes] valueForKey:@"representedObject"] valueForKey:key];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<arranged tree of %lu top-level node(s)>",
                                      (unsigned long)[[[controller _root] childNodes] count]];
}
@end

/* ---- NSTreeController --------------------------------------------------------------- */

/* A new arrangement before it is put in place: each node's new children
 * and leafness, by node, and each node's index path in it. */
@interface ATreePlan : NSObject {
@public
    NSMutableDictionary *kids;      /* node -> its new children */
    NSMutableDictionary *leaves;    /* node -> @0 or @1 */
    NSMutableDictionary *paths;     /* node -> its index path */
    NSMutableArray *objects;        /* every object in the tree, each once */
    NSMutableSet *seen;
}
@end
@implementation ATreePlan
- (instancetype)init
{
    if ((self = [super init])) {
        kids = [[NSMutableDictionary alloc] init];
        leaves = [[NSMutableDictionary alloc] init];
        paths = [[NSMutableDictionary alloc] init];
        objects = [[NSMutableArray alloc] init];
        seen = [[NSMutableSet alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [kids release];
    [leaves release];
    [paths release];
    [objects release];
    [seen release];
    [super dealloc];
}
- (NSArray *)kidsOf:(NSTreeNode *)n { return [kids objectForKey:ptr(n)] ?: [NSArray array]; }
- (NSIndexPath *)pathOf:(NSTreeNode *)n { return [paths objectForKey:ptr(n)]; }
- (NSTreeNode *)nodeAt:(NSIndexPath *)path from:(NSTreeNode *)root
{
    NSTreeNode *n = root;
    for (NSUInteger i = 0; n && i < [path length]; i++) {
        NSArray *k = [self kidsOf:n];
        NSUInteger at = [path indexAtPosition:i];
        n = at < [k count] ? [k objectAtIndex:at] : nil;
    }
    return n;
}
@end

static NSArray *selection_keys(void)
{
    static NSArray *keys;
    if (!keys)
        keys = [@[ @"selectionIndexPaths", @"selectionIndexPath", @"selectedNodes", @"selectedObjects", @"selection",
                   @"canRemove", @"canAddChild", @"canInsertChild" ] retain];
    return keys;
}

static NSArray *sorted_paths(NSArray *paths)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id p in paths)
        if ([p isKindOfClass:[NSIndexPath class]] && [p length] && ![out containsObject:p])
            [out addObject:p];
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

@implementation NSTreeController {
    id _items;                       /* the content: an array, a set or one object */
    NSTreeNode *_rootNode;           /* stands for the content; its children are the top level */
    ATreeArranged *_arrangedProxy;
    AArraySelection *_selectionProxy;
    NSArray *_selection;             /* sorted index paths */
    NSArray *_sortDescriptors;
    NSString *_childrenKeyPath, *_countKeyPath, *_leafKeyPath;
    BOOL _avoidsEmpty, _preserves, _selectsInserted, _alwaysMultiple;
    BOOL _editingContent;            /* changing the bound content: its change is ours */
    BOOL _mutating, _dirty;          /* changing the objects' children: arranged once, after */
    NSArray *_watchedObjects;        /* observed for their children */
    NSArray *_watchedKeys;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    static NSSet *manual;
    if (!manual)
        manual = [[NSSet setWithArray:@[ @"content", @"arrangedObjects", @"selectionIndexPaths", @"selectionIndexPath",
                                                 @"selectedNodes", @"selectedObjects", @"selection", @"canRemove",
                                                 @"canAddChild", @"canInsertChild", @"sortDescriptors" ]] retain];
    return [manual containsObject:key] ? NO : [super automaticallyNotifiesObserversForKey:key];
}

- (instancetype)initWithContent:(id)content
{
    if ((self = [super initWithContent:nil])) {
        _rootNode = [[NSTreeNode alloc] initWithRepresentedObject:nil];
        _arrangedProxy = [[ATreeArranged alloc] init];
        _arrangedProxy->controller = self;
        _selectionProxy = [[AArraySelection alloc] init];
        _selectionProxy->controller = self;
        _selection = [[NSArray alloc] init];
        _avoidsEmpty = _preserves = _selectsInserted = YES;
        if (content)
            [self setContent:content];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    /* the key names are a guess at Interface Builder's */
    for (NSString *k in @[ @"NSTreeContentChildrenKey", @"NSTreeContentCountKey", @"NSTreeContentLeafKey" ]) {
        id v = [coder containsValueForKey:k] ? [coder decodeObjectForKey:k] : nil;
        if (![v isKindOfClass:[NSString class]])
            continue;
        if ([k isEqualToString:@"NSTreeContentChildrenKey"])
            [self setChildrenKeyPath:v];
        else if ([k isEqualToString:@"NSTreeContentCountKey"])
            [self setCountKeyPath:v];
        else
            [self setLeafKeyPath:v];
    }
    if ([coder containsValueForKey:@"NSAvoidsEmptySelection"])
        _avoidsEmpty = [coder decodeBoolForKey:@"NSAvoidsEmptySelection"];
    if ([coder containsValueForKey:@"NSPreservesSelection"])
        _preserves = [coder decodeBoolForKey:@"NSPreservesSelection"];
    if ([coder containsValueForKey:@"NSSelectsInsertedObjects"])
        _selectsInserted = [coder decodeBoolForKey:@"NSSelectsInsertedObjects"];
    if ([coder containsValueForKey:@"NSAlwaysUsesMultipleValuesMarker"])
        _alwaysMultiple = [coder decodeBoolForKey:@"NSAlwaysUsesMultipleValuesMarker"];
    return self;
}
- (void)awakeFromNib
{
    if ([self automaticallyPreparesContent] && !_items && ![self infoForBinding:NSContentArrayBinding] &&
        ![self infoForBinding:NSContentSetBinding] && ![self infoForBinding:NSContentObjectBinding])
        [self prepareContent];
}
- (void)dealloc
{
    [self _watchObjects:nil];
    if (_arrangedProxy) {
        [_arrangedProxy _sourceWillChange];
        _arrangedProxy->controller = nil;
    }
    if (_selectionProxy) {
        [_selectionProxy _sourceWillChange];
        _selectionProxy->controller = nil;
    }
    [_arrangedProxy release];
    [_selectionProxy release];
    [_rootNode release];
    [_items release];
    [_selection release];
    [_sortDescriptors release];
    [_childrenKeyPath release];
    [_countKeyPath release];
    [_leafKeyPath release];
    [super dealloc];
}

/* ---- the key paths ---- */

- (NSString *)childrenKeyPath { return _childrenKeyPath; }
- (void)setChildrenKeyPath:(NSString *)p
{
    [_childrenKeyPath autorelease];
    _childrenKeyPath = [p copy];
    [self rearrangeObjects];
}
- (NSString *)countKeyPath { return _countKeyPath; }
- (void)setCountKeyPath:(NSString *)p
{
    [_countKeyPath autorelease];
    _countKeyPath = [p copy];
    [self rearrangeObjects];
}
- (NSString *)leafKeyPath { return _leafKeyPath; }
- (void)setLeafKeyPath:(NSString *)p
{
    [_leafKeyPath autorelease];
    _leafKeyPath = [p copy];
    [self rearrangeObjects];
}
- (NSString *)childrenKeyPathForNode:(NSTreeNode *)node { return _childrenKeyPath; }
- (NSString *)countKeyPathForNode:(NSTreeNode *)node { return _countKeyPath; }
- (NSString *)leafKeyPathForNode:(NSTreeNode *)node { return _leafKeyPath; }

/* ---- the content ---- */

- (id)content { return _items; }
- (NSArray *)_topObjects
{
    if (!_items)
        return [NSArray array];
    if ([_items isKindOfClass:[NSArray class]])
        return _items;
    if ([_items isKindOfClass:[NSSet class]])
        return [_items allObjects];
    return [NSArray arrayWithObject:_items];
}
- (void)_takeContent:(id)content
{
    if (content == _items)
        return;
    [self willChangeValueForKey:@"content"];
    [content retain];
    [_items release];
    _items = content;
    [self didChangeValueForKey:@"content"];
}
- (void)setContent:(id)content
{
    [self _takeContent:content];
    [self rearrangeObjects];
}
- (void)prepareContent { [self setContent:[NSMutableArray array]]; }
- (NSTreeNode *)_root { return _rootNode; }
- (id)arrangedObjects { return _arrangedProxy; }
- (NSArray *)_allObjects { return _watchedObjects ?: [NSArray array]; }

/* ---- arranging ---- */

/* An object's children, or nil for a leaf (and for an object without the
 * key). *leaf: whether it is one. */
- (NSArray *)_childrenOf:(id)object node:(NSTreeNode *)node leaf:(BOOL *)leaf
{
    NSString *leafPath = [self leafKeyPathForNode:node], *countPath = [self countKeyPathForNode:node];
    NSString *childrenPath = [self childrenKeyPathForNode:node];
    id kids = nil;
    *leaf = NO;
    @try {
        if (leafPath && truth([object valueForKeyPath:leafPath])) {
            *leaf = YES;
            return nil;
        }
        if (!leafPath && countPath && ![[object valueForKeyPath:countPath] unsignedIntegerValue]) {
            *leaf = YES;
            return nil;
        }
        kids = childrenPath ? [object valueForKeyPath:childrenPath] : nil;
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException])
            @throw;
        kids = nil;
    }
    if ([kids isKindOfClass:[NSSet class]])
        kids = [kids allObjects];
    if (![kids isKindOfClass:[NSArray class]])
        kids = nil;
    if (!leafPath && !countPath && ![kids count])
        *leaf = YES;
    return kids;
}
- (NSArray *)_arranged:(NSArray *)objects
{
    return [_sortDescriptors count] ? [objects sortedArrayUsingDescriptors:_sortDescriptors] : objects;
}
/* Plans node's children for these objects, reusing its old children for
 * the same objects. An object already above in the tree isn't followed
 * again (a loop). */
- (void)_plan:(ATreePlan *)plan node:(NSTreeNode *)node objects:(NSArray *)objects path:(NSIndexPath *)path
    ancestors:(NSMutableArray *)ancestors
{
    NSMutableArray *old = [[node->_children mutableCopy] autorelease];
    NSMutableArray *kids = [NSMutableArray array];
    for (id obj in [self _arranged:objects]) {
        NSTreeNode *c = nil;
        for (NSTreeNode *o in old)
            if (o->_object == obj) {
                c = o;
                break;
            }
        if (c)
            [old removeObjectIdenticalTo:c];
        else
            c = [[[NSTreeNode alloc] initWithRepresentedObject:obj] autorelease];
        NSIndexPath *p = [path indexPathByAddingIndex:[kids count]];
        [kids addObject:c];
        [plan->paths setObject:p forKey:ptr(c)];
        if (![plan->seen containsObject:ptr(obj)]) {
            [plan->seen addObject:ptr(obj)];
            [plan->objects addObject:obj];
        }
        BOOL leaf = YES;
        NSArray *grand = nil;
        if ([ancestors indexOfObjectIdenticalTo:obj] == NSNotFound)
            grand = [self _childrenOf:obj node:c leaf:&leaf];
        [plan->leaves setObject:@(leaf) forKey:ptr(c)];
        [ancestors addObject:obj];
        [self _plan:plan node:c objects:grand ?: @[] path:p ancestors:ancestors];
        [ancestors removeLastObject];
    }
    [plan->kids setObject:kids forKey:ptr(node)];
}
- (void)_apply:(ATreePlan *)plan node:(NSTreeNode *)node
{
    NSArray *kids = [plan kidsOf:node];
    for (NSTreeNode *o in node->_children)
        if ([kids indexOfObjectIdenticalTo:o] == NSNotFound && o->_parent == node)
            o->_parent = nil;
    [node->_children setArray:kids];
    for (NSTreeNode *c in kids) {
        c->_parent = node;
        c->_leaf = [[plan->leaves objectForKey:ptr(c)] boolValue] ? 1 : 0;
        [self _apply:plan node:c];
    }
}
/* Arranges the tree again. choose (nil: the usual rules) picks the new
 * selection in the new arrangement. */
- (void)_rearrangeChoosing:(NSArray * (^)(ATreePlan *plan))choose
{
    ATreePlan *plan = [[[ATreePlan alloc] init] autorelease];
    [self _plan:plan node:_rootNode objects:[self _topObjects] path:[[[NSIndexPath alloc] init] autorelease]
        ancestors:[NSMutableArray array]];
    NSArray *selection;
    if (choose) {
        selection = choose(plan);
    } else if (_preserves) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSTreeNode *n in [self selectedNodes]) {
            NSIndexPath *p = [plan pathOf:n];
            if (p)
                [a addObject:p];
        }
        selection = a;
    } else {
        NSMutableArray *a = [NSMutableArray array];
        for (NSIndexPath *p in _selection)
            if ([plan nodeAt:p from:_rootNode])
                [a addObject:p];
        selection = a;
    }
    selection = sorted_paths(selection);
    if (![selection count] && _avoidsEmpty && [[plan kidsOf:_rootNode] count] && !choose)
        selection = @[ [NSIndexPath indexPathWithIndex:0] ];
    [self _commit:plan selection:selection];
}
- (void)_commit:(ATreePlan *)plan selection:(NSArray *)selection
{
    NSArray *oldNodes = [self selectedNodes];
    NSMutableArray *newNodes = [NSMutableArray array], *valid = [NSMutableArray array];
    for (NSIndexPath *p in selection) {
        NSTreeNode *n = [plan nodeAt:p from:_rootNode];
        if (n) {
            [newNodes addObject:n];
            [valid addObject:p];
        }
    }
    selection = valid;
    BOOL changes = ![selection isEqualToArray:_selection] || ![oldNodes isEqualToArray:newNodes];
    if (changes) {
        for (NSString *k in selection_keys())
            [self willChangeValueForKey:k];
        [_selectionProxy _sourceWillChange];
    }
    [self willChangeValueForKey:@"arrangedObjects"];
    [_arrangedProxy _sourceWillChange];
    [self _apply:plan node:_rootNode];
    [self _watchObjects:plan->objects];
    id wasSelection = _selection;
    _selection = [selection copy];
    [wasSelection release];
    [_arrangedProxy _sourceDidChange];
    [self didChangeValueForKey:@"arrangedObjects"];
    if (changes) {
        [_selectionProxy _sourceDidChange];
        for (NSString *k in [selection_keys() reverseObjectEnumerator])
            [self didChangeValueForKey:k];
        ABindingPush(self, NSSelectionIndexPathsBinding);
    }
}
- (void)rearrangeObjects
{
    if (_mutating) {
        _dirty = YES;
        return;
    }
    [self _rearrangeChoosing:nil];
}
- (NSArray *)sortDescriptors { return _sortDescriptors ?: [NSArray array]; }
- (void)setSortDescriptors:(NSArray *)d
{
    [self willChangeValueForKey:@"sortDescriptors"];
    id wasSortDescriptors = _sortDescriptors;
    _sortDescriptors = [d copy];
    [wasSortDescriptors release];
    [self didChangeValueForKey:@"sortDescriptors"];
    ABindingPush(self, NSSortDescriptorsBinding);
    [self rearrangeObjects];
}

/* Every object of the tree is observed for its children, count and leaf
 * key paths; a change arranges the tree again. */
- (void)_watchObjects:(NSArray *)objects
{
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *k in @[ _childrenKeyPath ?: @"", _countKeyPath ?: @"", _leafKeyPath ?: @"" ])
        if ([k length] && ![keys containsObject:k])
            [keys addObject:k];
    if (!objects)
        keys = nil;
    NSMutableSet *now = [NSMutableSet set], *before = [NSMutableSet set];
    for (id o in objects)
        [now addObject:ptr(o)];
    for (id o in _watchedObjects)
        [before addObject:ptr(o)];
    BOOL sameKeys = [keys isEqualToArray:_watchedKeys ?: @[]] || (!keys && !_watchedKeys);
    for (id o in _watchedObjects)
        if (!sameKeys || ![now containsObject:ptr(o)])
            for (NSString *k in _watchedKeys)
                @try {
                    [o removeObserver:self forKeyPath:k context:&tree_context];
                } @catch (NSException *e) {
                }
    for (id o in objects)
        if (!sameKeys || ![before containsObject:ptr(o)])
            for (NSString *k in keys)
                @try {
                    [o addObserver:self forKeyPath:k options:0 context:&tree_context];
                } @catch (NSException *e) {
                }
    [_watchedObjects release];
    [_watchedKeys release];
    _watchedObjects = [objects copy];
    _watchedKeys = [keys copy];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == &tree_context) {
        [self rearrangeObjects];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

/* ---- the selection ---- */

- (id)selection { return _selectionProxy; }
- (NSArray *)selectionIndexPaths { return [[_selection retain] autorelease]; }
- (BOOL)setSelectionIndexPaths:(NSArray *)paths
{
    NSMutableArray *valid = [NSMutableArray array];
    for (NSIndexPath *p in sorted_paths(paths))
        if ([_rootNode descendantNodeAtIndexPath:p])
            [valid addObject:p];
    if ([valid isEqualToArray:_selection])
        return NO;
    for (NSString *k in selection_keys())
        [self willChangeValueForKey:k];
    [_selectionProxy _sourceWillChange];
    id wasSelection = _selection;
    _selection = [valid copy];
    [wasSelection release];
    [_selectionProxy _sourceDidChange];
    for (NSString *k in [selection_keys() reverseObjectEnumerator])
        [self didChangeValueForKey:k];
    ABindingPush(self, NSSelectionIndexPathsBinding);
    return YES;
}
- (NSIndexPath *)selectionIndexPath { return [_selection firstObject]; }
- (BOOL)setSelectionIndexPath:(NSIndexPath *)path { return [self setSelectionIndexPaths:path ? @[ path ] : @[]]; }
- (BOOL)addSelectionIndexPaths:(NSArray *)paths
{
    return [self setSelectionIndexPaths:[_selection arrayByAddingObjectsFromArray:paths ?: @[]]];
}
- (BOOL)removeSelectionIndexPaths:(NSArray *)paths
{
    NSMutableArray *a = [[_selection mutableCopy] autorelease];
    [a removeObjectsInArray:paths ?: @[]];
    return [self setSelectionIndexPaths:a];
}
- (NSArray *)selectedNodes
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSIndexPath *p in _selection) {
        NSTreeNode *n = [_rootNode descendantNodeAtIndexPath:p];
        if (n)
            [a addObject:n];
    }
    return a;
}
- (NSArray *)selectedObjects
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSTreeNode *n in [self selectedNodes])
        if (n->_object)
            [a addObject:n->_object];
    return a;
}
- (BOOL)avoidsEmptySelection { return _avoidsEmpty; }
- (void)setAvoidsEmptySelection:(BOOL)f { _avoidsEmpty = f; }
- (BOOL)preservesSelection { return _preserves; }
- (void)setPreservesSelection:(BOOL)f { _preserves = f; }
- (BOOL)selectsInsertedObjects { return _selectsInserted; }
- (void)setSelectsInsertedObjects:(BOOL)f { _selectsInserted = f; }
- (BOOL)alwaysUsesMultipleValuesMarker { return _alwaysMultiple; }
- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)f { _alwaysMultiple = f; }

/* ---- what can be done ---- */

/* A child goes under one selected node that its leaf key path doesn't
 * call a leaf; with a count key path the children aren't the
 * controller's to change. */
- (BOOL)_canTakeChild
{
    if (![self isEditable] || _countKeyPath || [_selection count] != 1)
        return NO;
    NSTreeNode *n = [[self selectedNodes] firstObject];
    NSString *leafPath = [self leafKeyPathForNode:n];
    if (!n || !n->_object)
        return NO;
    @try {
        return !(leafPath && truth([n->_object valueForKeyPath:leafPath]));
    } @catch (NSException *e) {
        return NO;
    }
}
- (BOOL)canAdd { return [self isEditable]; }
- (BOOL)canInsert { return [self isEditable]; }
- (BOOL)canAddChild { return [self _canTakeChild]; }
- (BOOL)canInsertChild { return [self _canTakeChild]; }
- (BOOL)canRemove { return [self isEditable] && [_selection count] > 0; }

/* ---- changing the objects ---- */

/* The objects under parent (the top level for the root), as the model
 * keeps them. */
- (NSArray *)_modelChildrenOf:(NSTreeNode *)parent
{
    if (parent == _rootNode)
        return [self _topObjects];
    BOOL leaf;
    return [self _childrenOf:parent->_object node:parent leaf:&leaf] ?: [NSArray array];
}
/* Puts object among parent's objects at index (NSNotFound: the end), or
 * takes it out (insert NO). */
- (void)_change:(NSTreeNode *)parent object:(id)object at:(NSUInteger)index insert:(BOOL)insert
{
    if (parent == _rootNode) {
        NSDictionary *arrayInfo = [self infoForBinding:NSContentArrayBinding];
        NSDictionary *setInfo = [self infoForBinding:NSContentSetBinding];
        NSArray *top = [self _topObjects];
        NSUInteger at = insert ? MIN(index, [top count]) : [top indexOfObjectIdenticalTo:object];
        if (!insert && at == NSNotFound)
            return;
        _editingContent = YES;
        @try {
            if (arrayInfo) {
                id observed = [arrayInfo objectForKey:NSObservedObjectKey];
                NSString *path = [arrayInfo objectForKey:NSObservedKeyPathKey];
                NSMutableArray *m = [observed mutableArrayValueForKeyPath:path];
                if (insert)
                    [m insertObject:object atIndex:at];
                else
                    [m removeObjectAtIndex:at];
                [self _takeContent:[observed valueForKeyPath:path]];
            } else if (setInfo) {
                id observed = [setInfo objectForKey:NSObservedObjectKey];
                NSString *path = [setInfo objectForKey:NSObservedKeyPathKey];
                NSMutableSet *m = [observed mutableSetValueForKeyPath:path];
                if (insert)
                    [m addObject:object];
                else
                    [m removeObject:object];
                [self _takeContent:[observed valueForKeyPath:path]];
            } else if ([_items isKindOfClass:[NSSet class]]) {
                NSMutableSet *s = [_items isKindOfClass:[NSMutableSet class]] ? [[_items retain] autorelease]
                                                                             : [[_items mutableCopy] autorelease];
                if (insert)
                    [s addObject:object];
                else
                    [s removeObject:object];
                [self _takeContent:s];
            } else {
                NSMutableArray *a = [_items isKindOfClass:[NSMutableArray class]] ? [[_items retain] autorelease]
                                                                                  : [NSMutableArray arrayWithArray:top];
                if (insert)
                    [a insertObject:object atIndex:at];
                else
                    [a removeObjectAtIndex:at];
                [self _takeContent:a];
            }
        } @finally {
            _editingContent = NO;
        }
        return;
    }
    id model = parent->_object;
    NSString *path = [self childrenKeyPathForNode:parent];
    if (!path)
        return;
    id now = [model valueForKeyPath:path];
    if ([now isKindOfClass:[NSSet class]]) {
        if ([model isKindOfClass:[NSDictionary class]]) {
            NSMutableSet *s = [[now mutableCopy] autorelease];
            if (insert)
                [s addObject:object];
            else
                [s removeObject:object];
            [model setValue:s forKeyPath:path];
        } else if (insert) {
            [[model mutableSetValueForKeyPath:path] addObject:object];
        } else {
            [[model mutableSetValueForKeyPath:path] removeObject:object];
        }
        return;
    }
    NSArray *list = [now isKindOfClass:[NSArray class]] ? now : [NSArray array];
    NSUInteger at = insert ? MIN(index, [list count]) : [list indexOfObjectIdenticalTo:object];
    if (!insert && at == NSNotFound)
        return;
    if (![model isKindOfClass:[NSDictionary class]]) {
        @try {
            NSMutableArray *m = [model mutableArrayValueForKeyPath:path];
            if (insert)
                [m insertObject:object atIndex:at];
            else
                [m removeObjectAtIndex:at];
            return;
        } @catch (NSException *e) {
            if (![[e name] isEqualToString:NSUndefinedKeyException])
                @throw;
        }
    }
    /* a dictionary (or an object with no way in): a changed copy */
    NSMutableArray *a = [NSMutableArray arrayWithArray:list];
    if (insert)
        [a insertObject:object atIndex:at];
    else
        [a removeObjectAtIndex:at];
    [model setValue:a forKeyPath:path];
}
/* Runs a change of the objects, arranging the tree once after it. */
- (void)_mutate:(void (^)(void))change choosing:(NSArray * (^)(ATreePlan *plan))choose
{
    BOOL was = _mutating;
    _mutating = YES;
    @try {
        change();
    } @finally {
        _mutating = was;
    }
    if (!was) {
        _dirty = NO;
        [self _rearrangeChoosing:choose];
    }
}
/* Where an object put at arranged index i among parent's nodes goes among
 * the model's objects: before the object arranged there. */
- (NSUInteger)_modelIndexFor:(NSUInteger)i under:(NSTreeNode *)parent
{
    NSArray *kids = parent->_children;
    NSArray *model = [self _modelChildrenOf:parent];
    if (i < [kids count]) {
        NSUInteger at = [model indexOfObjectIdenticalTo:((NSTreeNode *)[kids objectAtIndex:i])->_object];
        if (at != NSNotFound)
            return at;
    }
    return [model count];
}
- (void)insertObject:(id)object atArrangedObjectIndexPath:(NSIndexPath *)path
{
    if (object && path)
        [self insertObjects:@[ object ] atArrangedObjectIndexPaths:@[ path ]];
}
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexPaths:(NSArray *)paths
{
    if (![objects count] || [objects count] != [paths count])
        return;
    NSMutableArray *parents = [NSMutableArray array];
    for (NSIndexPath *p in paths) {
        NSTreeNode *parent = [p length] ? [_rootNode descendantNodeAtIndexPath:[p indexPathByRemovingLastIndex]] : nil;
        if (!parent || ![p length])
            [NSException raise:NSRangeException format:@"-[NSTreeController insertObjects:atArrangedObjectIndexPaths:]: "
                                                        @"no node at %@", [p indexPathByRemovingLastIndex]];
        [parents addObject:parent];
    }
    [self _mutate:^{
        for (NSUInteger i = 0; i < [objects count]; i++) {
            NSTreeNode *parent = [parents objectAtIndex:i];
            NSUInteger at = [self _modelIndexFor:[[paths objectAtIndex:i] indexAtPosition:[[paths objectAtIndex:i] length] - 1]
                                           under:parent];
            [self _change:parent object:[objects objectAtIndex:i] at:at insert:YES];
        }
    }
        choosing:^NSArray *(ATreePlan *plan) {
            NSArray *keep = [self selectedNodes];
            NSMutableArray *sel = [NSMutableArray array];
            if (_selectsInserted) {
                for (NSUInteger i = 0; i < [objects count]; i++)
                    for (NSTreeNode *c in [plan kidsOf:[parents objectAtIndex:i]])
                        if (c->_object == [objects objectAtIndex:i]) {
                            [sel addObject:[plan pathOf:c]];
                            break;
                        }
            } else {
                for (NSTreeNode *n in keep)
                    if ([plan pathOf:n])
                        [sel addObject:[plan pathOf:n]];
            }
            return sel;
        }];
}
- (void)removeObjectAtArrangedObjectIndexPath:(NSIndexPath *)path
{
    if (path)
        [self removeObjectsAtArrangedObjectIndexPaths:@[ path ]];
}
- (void)removeObjectsAtArrangedObjectIndexPaths:(NSArray *)paths
{
    NSArray *sorted = sorted_paths(paths);
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSIndexPath *p in sorted) {
        NSTreeNode *n = [_rootNode descendantNodeAtIndexPath:p];
        if (!n)
            continue;
        BOOL under = NO;   /* an ancestor goes too: this goes with it */
        for (NSTreeNode *a = n->_parent; a && !under; a = a->_parent)
            under = [nodes indexOfObjectIdenticalTo:a] != NSNotFound;
        if (!under)
            [nodes addObject:n];
    }
    if (![nodes count])
        return;
    NSIndexPath *first = [[nodes firstObject] indexPath];
    NSTreeNode *firstParent = ((NSTreeNode *)[nodes firstObject])->_parent;
    [self _mutate:^{
        for (NSTreeNode *n in [nodes reverseObjectEnumerator])
            [self _change:n->_parent object:n->_object at:0 insert:NO];
    }
        choosing:^NSArray *(ATreePlan *plan) {
            NSMutableArray *sel = [NSMutableArray array];
            for (NSTreeNode *n in [self selectedNodes]) {
                NSIndexPath *p = [plan pathOf:n];
                BOOL gone = NO;
                for (NSTreeNode *a = n; a && !gone; a = a->_parent)
                    gone = [nodes indexOfObjectIdenticalTo:a] != NSNotFound;
                if (p && !gone)
                    [sel addObject:p];
            }
            if (![sel count] && _avoidsEmpty) {
                /* the node now where the first removed one was, else its parent */
                NSArray *kids = [plan kidsOf:firstParent];
                NSIndexPath *parentPath = firstParent == _rootNode ? nil : [plan pathOf:firstParent];
                if ([kids count]) {
                    NSUInteger at = MIN([first indexAtPosition:[first length] - 1], [kids count] - 1);
                    [sel addObject:[plan pathOf:[kids objectAtIndex:at]]];
                } else if (parentPath) {
                    [sel addObject:parentPath];
                }
            }
            return sel;
        }];
}
- (void)moveNode:(NSTreeNode *)node toIndexPath:(NSIndexPath *)path
{
    if (node)
        [self moveNodes:@[ node ] toIndexPath:path];
}
/* The nodes' objects leave their parents and go, in order, under the node
 * at the path's parent, from its last index on; they are then selected. */
- (void)moveNodes:(NSArray *)nodes toIndexPath:(NSIndexPath *)path
{
    if (![nodes count] || ![path length])
        return;
    NSTreeNode *target = [_rootNode descendantNodeAtIndexPath:[path indexPathByRemovingLastIndex]];
    if (!target)
        [NSException raise:NSRangeException format:@"-[NSTreeController moveNodes:toIndexPath:]: no node at %@",
                                                    [path indexPathByRemovingLastIndex]];
    NSUInteger start = [path indexAtPosition:[path length] - 1];
    NSMutableArray *objects = [NSMutableArray array];
    for (NSTreeNode *n in nodes)
        [objects addObject:n->_object ?: [NSNull null]];
    [self _mutate:^{
        /* the arranged index counts the target's nodes left after the move */
        NSMutableArray *staying = [[target->_children mutableCopy] autorelease];
        [staying removeObjectsInArray:nodes];
        id anchor = start < [staying count] ? ((NSTreeNode *)[staying objectAtIndex:start])->_object : nil;
        for (NSTreeNode *n in nodes)
            if (n->_parent)
                [self _change:n->_parent object:n->_object at:0 insert:NO];
        NSArray *model = [self _modelChildrenOf:target];
        NSUInteger at = anchor ? [model indexOfObjectIdenticalTo:anchor] : NSNotFound;
        if (at == NSNotFound)
            at = [model count];
        for (id o in objects)
            if (o != [NSNull null])
                [self _change:target object:o at:at++ insert:YES];
    }
        choosing:^NSArray *(ATreePlan *plan) {
            NSMutableArray *sel = [NSMutableArray array];
            for (NSTreeNode *c in [plan kidsOf:target])
                if ([objects indexOfObjectIdenticalTo:c->_object] != NSNotFound)
                    [sel addObject:[plan pathOf:c]];
            return sel;
        }];
}

/* ---- the actions: carried out on the run loop's next turn ---- */

- (void)_insertNew:(NSTreeNode *)parent at:(NSUInteger)index
{
    id obj = [self newObject];
    NSIndexPath *where = parent == _rootNode ? [NSIndexPath indexPathWithIndex:index]
                                             : [[parent indexPath] indexPathByAddingIndex:index];
    [self insertObject:obj atArrangedObjectIndexPath:where];
    [obj release];
}
- (void)add:(id)sender { [self performSelector:@selector(_ferryAdd) withObject:nil afterDelay:0]; }
- (void)insert:(id)sender { [self performSelector:@selector(_ferryInsert) withObject:nil afterDelay:0]; }
- (void)addChild:(id)sender { [self performSelector:@selector(_ferryAddChild) withObject:nil afterDelay:0]; }
- (void)insertChild:(id)sender { [self performSelector:@selector(_ferryInsertChild) withObject:nil afterDelay:0]; }
- (void)_ferryAdd
{
    NSTreeNode *sel = [[self selectedNodes] firstObject];
    NSTreeNode *parent = sel ? sel->_parent : _rootNode;
    [self _insertNew:parent at:[parent->_children count]];
}
- (void)_ferryInsert
{
    NSTreeNode *sel = [[self selectedNodes] firstObject];
    if (!sel) {
        [self _insertNew:_rootNode at:0];
        return;
    }
    [self _insertNew:sel->_parent at:[sel->_parent->_children indexOfObjectIdenticalTo:sel]];
}
- (void)_ferryAddChild
{
    if (![self _canTakeChild])
        return;
    NSTreeNode *sel = [[self selectedNodes] firstObject];
    [self _insertNew:sel at:[sel->_children count]];
}
- (void)_ferryInsertChild
{
    if (![self _canTakeChild])
        return;
    [self _insertNew:[[self selectedNodes] firstObject] at:0];
}
- (void)_ferryRemove { [self removeObjectsAtArrangedObjectIndexPaths:_selection]; }
/* NSObjectController's addObject: and removeObject:, for the tree's top */
- (void)addObject:(id)object
{
    if (object)
        [self insertObject:object atArrangedObjectIndexPath:[NSIndexPath indexPathWithIndex:[_rootNode->_children count]]];
}
- (void)removeObject:(id)object
{
    for (NSTreeNode *n in [[_rootNode->_children copy] autorelease])
        if (n->_object == object) {
            [self removeObjectAtArrangedObjectIndexPath:[n indexPath]];
            return;
        }
}

/* ---- bindings ---- */

- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentArrayBinding] || [binding isEqualToString:NSContentSetBinding] ||
        [binding isEqualToString:NSContentObjectBinding] || [binding isEqualToString:NSContentBinding]) {
        if (NSIsControllerMarker(value))
            value = nil;
        if (_editingContent)
            [self _takeContent:value];   /* our own change, arranged by us */
        else
            [self setContent:value];
    } else if ([binding isEqualToString:NSSelectionIndexPathsBinding]) {
        [self setSelectionIndexPaths:[value isKindOfClass:[NSArray class]] ? value : @[]];
    } else if ([binding isEqualToString:NSSortDescriptorsBinding]) {
        NSArray *d = [value isKindOfClass:[NSArray class]] ? value : nil;
        if (!(d == _sortDescriptors || [d isEqual:_sortDescriptors]))
            [self setSortDescriptors:d];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentArrayBinding] || [binding isEqualToString:NSContentSetBinding] ||
        [binding isEqualToString:NSContentObjectBinding] || [binding isEqualToString:NSContentBinding])
        return _items;
    if ([binding isEqualToString:NSSelectionIndexPathsBinding])
        return [self selectionIndexPaths];
    if ([binding isEqualToString:NSSortDescriptorsBinding])
        return [self sortDescriptors];
    return [super _ferryValueForBinding:binding];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: %lu top-level of %lu, %lu selected>", [self class], self,
                                      (unsigned long)[_rootNode->_children count],
                                      (unsigned long)[_watchedObjects count], (unsigned long)[_selection count]];
}
@end

/* ---- index paths as collection views use them ---- */

@implementation NSIndexPath (NSCollectionViewAdditions)
+ (NSIndexPath *)indexPathForItem:(NSInteger)item inSection:(NSInteger)section
{
    NSUInteger i[2] = {(NSUInteger)section, (NSUInteger)item};
    return [NSIndexPath indexPathWithIndexes:i length:2];
}
- (NSInteger)section { return (NSInteger)[self indexAtPosition:0]; }
- (NSInteger)item { return (NSInteger)[self indexAtPosition:1]; }
@end
