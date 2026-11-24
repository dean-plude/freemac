/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSArrayController, as Apple's public documentation describes it. No
 * Apple code was used.
 *
 * Its content is an array (or a set), given with setContent: or by the
 * contentArray or contentSet binding. What it shows, arrangedObjects, is
 * the content filtered by filterPredicate and sorted by sortDescriptors;
 * a selection of those (selectionIndexes) is what "selection.someKey"
 * reads and writes: the one value the selected objects share, or
 * NSMultipleValuesMarker when they disagree, NSNoSelectionMarker when
 * nothing is selected, NSNotApplicableMarker for a key they don't have.
 *
 * Objects added or inserted go at the end of the arranged objects (or at
 * the index given), not sorted until the objects are rearranged, unless
 * automaticallyRearrangesObjects is on; with selectsInsertedObjects they
 * become the selection. preservesSelection keeps the selected objects
 * selected when the arrangement changes, avoidsEmptySelection selects
 * something when content arrives or the selected objects go. With the
 * contentArray or contentSet binding, adding and removing change the bound
 * array or set, through mutableArrayValueForKeyPath: and
 * mutableSetValueForKeyPath:, so its owner hears of each change. The add:,
 * insert: and remove: actions are carried out on the run loop's next turn.
 *
 * Observers of "arrangedObjects.someKey" hear of that key changing on any
 * of the arranged objects (so a table column bound to it is redrawn), as
 * well as of new arranged objects. */
#import "AInternal.h"

NSString *const NSContentArrayBinding = @"contentArray";
NSString *const NSContentSetBinding = @"contentSet";
NSString *const NSSelectionIndexesBinding = @"selectionIndexes";
NSString *const NSSortDescriptorsBinding = @"sortDescriptors";
NSString *const NSFilterPredicateBinding = @"filterPredicate";

@interface NSPredicate (FerryKeyPaths)
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)paths;
@end

static NSString *first_key(NSString *keyPath)
{
    NSRange dot = [keyPath rangeOfString:@"."];
    return dot.location == NSNotFound ? keyPath : [keyPath substringToIndex:dot.location];
}

/* The objects, each once, in their order. */
static NSArray *distinct(NSArray *objects)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id o in objects)
        if ([out indexOfObjectIdenticalTo:o] == NSNotFound)
            [out addObject:o];
    return out;
}

/* Where each object is in `in`, by identity. */
static NSIndexSet *indexes_of(NSArray *objects, NSArray *in)
{
    NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
    for (id o in objects) {
        NSUInteger i = [in indexOfObjectIdenticalTo:o];
        if (i != NSNotFound)
            [s addIndex:i];
    }
    return s;
}

static BOOL same_objects(NSArray *a, NSArray *b)
{
    if ([a count] != [b count])
        return NO;
    for (NSUInteger i = 0; i < [a count]; i++)
        if ([a objectAtIndex:i] != [b objectAtIndex:i])
            return NO;
    return YES;
}

@interface AArrangedObjects : NSArray {
@public
    NSArrayController *controller;   /* not retained: it owns us */
    NSMutableDictionary *_keys;      /* first key observed on us -> how many times */
    NSArray *_watched;               /* the objects those keys are observed on */
}
- (void)_contentWillChange;
- (void)_contentDidChange;
@end

@implementation NSArrayController {
    id _items;                       /* the content: an array or a set */
    NSMutableArray *_arranged;
    AArrangedObjects *_arrangedProxy;
    AArraySelection *_selectionProxy;
    NSIndexSet *_selectionIndexes;
    NSArray *_sortDescriptors;
    NSPredicate *_filterPredicate;
    BOOL _avoidsEmpty, _preserves, _selectsInserted, _clearsFilter, _autoRearranges, _alwaysMultiple;
    BOOL _editingContent;            /* changing the bound array: its change is ours */
    NSArray *_rearrangeWatched;      /* objects observed for automatic rearranging */
    NSArray *_rearrangeKeys;         /* and the key paths observed on them */
}

static char rearrange_context;

static NSArray *selection_keys(void)
{
    static NSArray *keys;
    if (!keys)
        keys = [@[ @"selectionIndexes", @"selectionIndex", @"selectedObjects", @"selection", @"canRemove",
                   @"canSelectNext", @"canSelectPrevious" ] retain];
    return keys;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    static NSSet *manual;
    if (!manual)
        manual = [[NSSet setWithArray:@[ @"content", @"contentArray", @"arrangedObjects", @"selectionIndexes",
                                                 @"selectionIndex", @"selectedObjects", @"selection", @"canRemove",
                                                 @"canSelectNext", @"canSelectPrevious", @"sortDescriptors",
                                                 @"filterPredicate" ]] retain];
    return [manual containsObject:key] ? NO : [super automaticallyNotifiesObserversForKey:key];
}

- (instancetype)initWithContent:(id)content
{
    if ((self = [super initWithContent:nil])) {
        _arranged = [[NSMutableArray alloc] init];
        _arrangedProxy = [[AArrangedObjects alloc] init];
        _arrangedProxy->controller = self;
        _selectionProxy = [[AArraySelection alloc] init];
        _selectionProxy->controller = self;
        _selectionIndexes = [[NSIndexSet alloc] init];
        _avoidsEmpty = _preserves = _selectsInserted = _clearsFilter = YES;
        if (content)
            [self setContent:content];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    /* the key names of Interface Builder's checkboxes are a guess */
    if ([coder containsValueForKey:@"NSAvoidsEmptySelection"])
        _avoidsEmpty = [coder decodeBoolForKey:@"NSAvoidsEmptySelection"];
    if ([coder containsValueForKey:@"NSPreservesSelection"])
        _preserves = [coder decodeBoolForKey:@"NSPreservesSelection"];
    if ([coder containsValueForKey:@"NSSelectsInsertedObjects"])
        _selectsInserted = [coder decodeBoolForKey:@"NSSelectsInsertedObjects"];
    if ([coder containsValueForKey:@"NSClearsFilterPredicateOnInsertion"])
        _clearsFilter = [coder decodeBoolForKey:@"NSClearsFilterPredicateOnInsertion"];
    if ([coder containsValueForKey:@"NSAutomaticallyRearrangesObjects"])
        _autoRearranges = [coder decodeBoolForKey:@"NSAutomaticallyRearrangesObjects"];
    return self;
}
- (void)awakeFromNib
{
    if ([self automaticallyPreparesContent] && !_items && ![self infoForBinding:NSContentArrayBinding] &&
        ![self infoForBinding:NSContentSetBinding])
        [self prepareContent];
}
- (void)dealloc
{
    [self _unwatchForRearranging];
    if (_arrangedProxy) {
        [_arrangedProxy _contentWillChange];
        _arrangedProxy->controller = nil;
    }
    if (_selectionProxy) {
        [_selectionProxy _sourceWillChange];
        _selectionProxy->controller = nil;
    }
    [_arrangedProxy release];
    [_selectionProxy release];
    [_items release];
    [_arranged release];
    [_selectionIndexes release];
    [_sortDescriptors release];
    [_filterPredicate release];
    [super dealloc];
}

/* ---- the content ---- */

- (id)content { return _items; }
/* The content's objects in its order (a set's in no particular one). */
- (NSArray *)_contentObjects
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
    [self willChangeValueForKey:@"contentArray"];
    [content retain];
    [_items release];
    _items = content;
    [self didChangeValueForKey:@"contentArray"];
    [self didChangeValueForKey:@"content"];
}
- (void)setContent:(id)content
{
    [self _takeContent:content];
    [self _rearrange];
}
- (NSArray *)contentArray { return [self _contentObjects]; }
- (void)prepareContent
{
    [self setContent:[NSMutableArray array]];
}

/* The arranged objects and the selection change together: observers of
 * the selection hear around observers of the arranged objects. */
- (void)_commitArranged:(NSArray *)arranged selection:(NSIndexSet *)selection
{
    NSArray *oldSelected = [self selectedObjects];
    NSMutableIndexSet *sel = [[selection mutableCopy] autorelease];
    [sel removeIndexesInRange:NSMakeRange([arranged count], NSNotFound - [arranged count])];
    NSArray *newSelected = [arranged objectsAtIndexes:sel];
    BOOL selectionChanges = ![sel isEqualToIndexSet:_selectionIndexes] || !same_objects(oldSelected, newSelected);
    if (selectionChanges) {
        for (NSString *k in selection_keys())
            [self willChangeValueForKey:k];
        [_selectionProxy _sourceWillChange];
    }
    [self willChangeValueForKey:@"arrangedObjects"];
    [_arrangedProxy _contentWillChange];
    [_arranged setArray:arranged];
    [_selectionIndexes release];
    _selectionIndexes = [sel copy];
    [_arrangedProxy _contentDidChange];
    [self didChangeValueForKey:@"arrangedObjects"];
    if (selectionChanges) {
        [_selectionProxy _sourceDidChange];
        for (NSString *k in [selection_keys() reverseObjectEnumerator])
            [self didChangeValueForKey:k];
        ABindingPush(self, NSSelectionIndexesBinding);
    }
    [self _watchForRearranging];
}
- (BOOL)_commitSelectionOnly:(NSIndexSet *)selection
{
    NSMutableIndexSet *sel = [[selection mutableCopy] autorelease] ?: [NSMutableIndexSet indexSet];
    [sel removeIndexesInRange:NSMakeRange([_arranged count], NSNotFound - [_arranged count])];
    if ([sel isEqualToIndexSet:_selectionIndexes])
        return NO;
    for (NSString *k in selection_keys())
        [self willChangeValueForKey:k];
    [_selectionProxy _sourceWillChange];
    [_selectionIndexes release];
    _selectionIndexes = [sel copy];
    [_selectionProxy _sourceDidChange];
    for (NSString *k in [selection_keys() reverseObjectEnumerator])
        [self didChangeValueForKey:k];
    ABindingPush(self, NSSelectionIndexesBinding);
    return YES;
}

/* ---- arranging ---- */

- (NSArray *)arrangeObjects:(NSArray *)objects
{
    NSArray *out = objects;
    if (_filterPredicate)
        out = [out filteredArrayUsingPredicate:_filterPredicate];
    if ([_sortDescriptors count])
        out = [out sortedArrayUsingDescriptors:_sortDescriptors];
    return out;
}
- (id)arrangedObjects { return _arrangedProxy; }
- (NSArray *)_arranged { return _arranged; }
/* The content arranged again; the selection follows the selected objects
 * (preservesSelection) or stays at its indexes. */
- (void)_rearrange
{
    NSArray *arranged = [self arrangeObjects:[self _contentObjects]];
    NSIndexSet *sel = _preserves ? indexes_of([self selectedObjects], arranged) : _selectionIndexes;
    if (![sel count] && _avoidsEmpty && [arranged count])
        sel = [NSIndexSet indexSetWithIndex:0];
    [self _commitArranged:arranged selection:sel];
}
- (void)rearrangeObjects { [self _rearrange]; }
- (NSArray *)sortDescriptors { return _sortDescriptors ?: [NSArray array]; }
- (void)setSortDescriptors:(NSArray *)d
{
    [self willChangeValueForKey:@"sortDescriptors"];
    [_sortDescriptors release];
    _sortDescriptors = [d copy];
    [self didChangeValueForKey:@"sortDescriptors"];
    ABindingPush(self, NSSortDescriptorsBinding);
    [self rearrangeObjects];
}
- (NSPredicate *)filterPredicate { return _filterPredicate; }
- (void)setFilterPredicate:(NSPredicate *)p
{
    [self willChangeValueForKey:@"filterPredicate"];
    [p retain];
    [_filterPredicate release];
    _filterPredicate = p;
    [self didChangeValueForKey:@"filterPredicate"];
    ABindingPush(self, NSFilterPredicateBinding);
    [self rearrangeObjects];
}
- (BOOL)clearsFilterPredicateOnInsertion { return _clearsFilter; }
- (void)setClearsFilterPredicateOnInsertion:(BOOL)f { _clearsFilter = f; }
- (BOOL)automaticallyRearrangesObjects { return _autoRearranges; }
- (void)setAutomaticallyRearrangesObjects:(BOOL)f
{
    _autoRearranges = f;
    [self _watchForRearranging];
}
/* The key paths whose change rearranges the objects: those the sort
 * descriptors and the filter predicate read. */
- (NSArray *)automaticRearrangementKeyPaths
{
    if (!_autoRearranges)
        return nil;
    NSMutableSet *paths = [NSMutableSet set];
    for (NSSortDescriptor *d in _sortDescriptors)
        if ([d key])
            [paths addObject:[d key]];
    if ([_filterPredicate respondsToSelector:@selector(_ferryAddKeyPathsTo:)])
        [_filterPredicate _ferryAddKeyPathsTo:paths];
    return [[paths allObjects] sortedArrayUsingSelector:@selector(compare:)];
}
- (void)didChangeArrangementCriteria
{
    [self _watchForRearranging];
}
- (void)_unwatchForRearranging
{
    for (id o in _rearrangeWatched)
        for (NSString *k in _rearrangeKeys)
            [o removeObserver:self forKeyPath:k context:&rearrange_context];
    [_rearrangeWatched release];
    [_rearrangeKeys release];
    _rearrangeWatched = _rearrangeKeys = nil;
}
- (void)_watchForRearranging
{
    NSArray *keys = [self automaticRearrangementKeyPaths];
    NSArray *objects = [keys count] ? distinct([self _contentObjects]) : nil;
    if (same_objects(objects ?: @[], _rearrangeWatched ?: @[]) && [keys isEqual:_rearrangeKeys])
        return;
    [self _unwatchForRearranging];
    if (![keys count])
        return;
    _rearrangeKeys = [keys copy];
    _rearrangeWatched = [objects copy];
    for (id o in _rearrangeWatched)
        for (NSString *k in _rearrangeKeys)
            [o addObserver:self forKeyPath:k options:0 context:&rearrange_context];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == &rearrange_context) {
        [self rearrangeObjects];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

/* ---- the selection ---- */

- (id)selection { return _selectionProxy; }
- (NSIndexSet *)selectionIndexes { return [[_selectionIndexes retain] autorelease]; }
- (BOOL)setSelectionIndexes:(NSIndexSet *)indexes { return [self _commitSelectionOnly:indexes]; }
- (NSUInteger)selectionIndex { return [_selectionIndexes count] ? [_selectionIndexes firstIndex] : NSNotFound; }
- (BOOL)setSelectionIndex:(NSUInteger)index
{
    return [self setSelectionIndexes:index == NSNotFound ? [NSIndexSet indexSet] : [NSIndexSet indexSetWithIndex:index]];
}
- (BOOL)addSelectionIndexes:(NSIndexSet *)indexes
{
    NSMutableIndexSet *s = [[_selectionIndexes mutableCopy] autorelease];
    [s addIndexes:indexes];
    return [self setSelectionIndexes:s];
}
- (BOOL)removeSelectionIndexes:(NSIndexSet *)indexes
{
    NSMutableIndexSet *s = [[_selectionIndexes mutableCopy] autorelease];
    [s removeIndexes:indexes];
    return [self setSelectionIndexes:s];
}
- (NSArray *)selectedObjects { return [_arranged objectsAtIndexes:_selectionIndexes]; }
- (BOOL)setSelectedObjects:(NSArray *)objects { return [self setSelectionIndexes:indexes_of(objects, _arranged)]; }
- (BOOL)addSelectedObjects:(NSArray *)objects { return [self addSelectionIndexes:indexes_of(objects, _arranged)]; }
- (BOOL)removeSelectedObjects:(NSArray *)objects
{
    return [self removeSelectionIndexes:indexes_of(objects, _arranged)];
}
- (BOOL)avoidsEmptySelection { return _avoidsEmpty; }
- (void)setAvoidsEmptySelection:(BOOL)f { _avoidsEmpty = f; }
- (BOOL)preservesSelection { return _preserves; }
- (void)setPreservesSelection:(BOOL)f { _preserves = f; }
- (BOOL)selectsInsertedObjects { return _selectsInserted; }
- (void)setSelectsInsertedObjects:(BOOL)f { _selectsInserted = f; }
- (BOOL)alwaysUsesMultipleValuesMarker { return _alwaysMultiple; }
- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)f { _alwaysMultiple = f; }
- (BOOL)canSelectNext
{
    return [_selectionIndexes count] && [_selectionIndexes lastIndex] + 1 < [_arranged count];
}
- (BOOL)canSelectPrevious { return [_selectionIndexes count] && [_selectionIndexes firstIndex] > 0; }
- (void)selectNext:(id)sender
{
    if ([self canSelectNext])
        [self setSelectionIndex:[_selectionIndexes lastIndex] + 1];
}
- (void)selectPrevious:(id)sender
{
    if ([self canSelectPrevious])
        [self setSelectionIndex:[_selectionIndexes firstIndex] - 1];
}

/* ---- adding and removing ---- */

- (BOOL)canAdd { return [self isEditable]; }
- (BOOL)canInsert { return [self isEditable]; }
- (BOOL)canRemove { return [self isEditable] && [_selectionIndexes count] > 0; }

/* The content changed in place: through the bound array or set, so that
 * its owner hears of it, or the controller's own array. */
- (void)_contentInsert:(NSArray *)objects atIndexes:(NSIndexSet *)indexes
{
    NSDictionary *arrayInfo = [self infoForBinding:NSContentArrayBinding];
    NSDictionary *setInfo = [self infoForBinding:NSContentSetBinding];
    _editingContent = YES;
    @try {
        if (arrayInfo) {
            id observed = [arrayInfo objectForKey:NSObservedObjectKey];
            NSString *path = [arrayInfo objectForKey:NSObservedKeyPathKey];
            [[observed mutableArrayValueForKeyPath:path] insertObjects:objects atIndexes:indexes];
            [self _takeContent:[observed valueForKeyPath:path]];
        } else if (setInfo) {
            id observed = [setInfo objectForKey:NSObservedObjectKey];
            NSString *path = [setInfo objectForKey:NSObservedKeyPathKey];
            [[observed mutableSetValueForKeyPath:path] addObjectsFromArray:objects];
            [self _takeContent:[observed valueForKeyPath:path]];
        } else if ([_items isKindOfClass:[NSSet class]]) {
            NSMutableSet *s = [_items isKindOfClass:[NSMutableSet class]] ? [[_items retain] autorelease]
                                                                         : [[_items mutableCopy] autorelease];
            [s addObjectsFromArray:objects];
            [self _takeContent:s];
        } else {
            NSMutableArray *a = [_items isKindOfClass:[NSMutableArray class]]
                                    ? [[_items retain] autorelease]
                                    : [NSMutableArray arrayWithArray:[self _contentObjects]];
            [a insertObjects:objects atIndexes:indexes];
            [self _takeContent:a];
        }
    } @finally {
        _editingContent = NO;
    }
}
- (void)_contentRemove:(NSArray *)objects
{
    NSDictionary *arrayInfo = [self infoForBinding:NSContentArrayBinding];
    NSDictionary *setInfo = [self infoForBinding:NSContentSetBinding];
    NSIndexSet *where = indexes_of(objects, [self _contentObjects]);
    _editingContent = YES;
    @try {
        if (arrayInfo) {
            id observed = [arrayInfo objectForKey:NSObservedObjectKey];
            NSString *path = [arrayInfo objectForKey:NSObservedKeyPathKey];
            [[observed mutableArrayValueForKeyPath:path] removeObjectsAtIndexes:where];
            [self _takeContent:[observed valueForKeyPath:path]];
        } else if (setInfo) {
            id observed = [setInfo objectForKey:NSObservedObjectKey];
            NSString *path = [setInfo objectForKey:NSObservedKeyPathKey];
            [[observed mutableSetValueForKeyPath:path] minusSet:[NSSet setWithArray:objects]];
            [self _takeContent:[observed valueForKeyPath:path]];
        } else if ([_items isKindOfClass:[NSSet class]]) {
            NSMutableSet *s = [_items isKindOfClass:[NSMutableSet class]] ? [[_items retain] autorelease]
                                                                         : [[_items mutableCopy] autorelease];
            [s minusSet:[NSSet setWithArray:objects]];
            [self _takeContent:s];
        } else {
            NSMutableArray *a = [_items isKindOfClass:[NSMutableArray class]]
                                    ? [[_items retain] autorelease]
                                    : [NSMutableArray arrayWithArray:[self _contentObjects]];
            [a removeObjectsAtIndexes:where];
            [self _takeContent:a];
        }
    } @finally {
        _editingContent = NO;
    }
}

/* New objects are in the content: they go at `arrangedIndexes` of the
 * arranged objects (or wherever arranging puts them). */
- (void)_insertedObjects:(NSArray *)objects atArrangedIndexes:(NSIndexSet *)arrangedIndexes
{
    NSArray *keep = [self selectedObjects];
    NSArray *arranged;
    if (_autoRearranges) {
        arranged = [self arrangeObjects:[self _contentObjects]];
    } else {
        NSMutableArray *a = [[_arranged mutableCopy] autorelease];
        [a insertObjects:objects atIndexes:arrangedIndexes];
        arranged = a;
    }
    NSIndexSet *sel = _selectsInserted ? indexes_of(objects, arranged) : indexes_of(keep, arranged);
    if (![sel count] && _avoidsEmpty && [arranged count])
        sel = [NSIndexSet indexSetWithIndex:0];
    [self _commitArranged:arranged selection:sel];
}
- (void)_clearFilterForInsertion
{
    if (_clearsFilter && _filterPredicate) {
        [self willChangeValueForKey:@"filterPredicate"];
        [_filterPredicate release];
        _filterPredicate = nil;
        [self didChangeValueForKey:@"filterPredicate"];
        ABindingPush(self, NSFilterPredicateBinding);
        NSArray *keep = [self selectedObjects];
        NSArray *arranged = [self arrangeObjects:[self _contentObjects]];
        [self _commitArranged:arranged selection:indexes_of(keep, arranged)];
    }
}
- (void)addObject:(id)object
{
    if (object)
        [self addObjects:[NSArray arrayWithObject:object]];
}
- (void)addObjects:(NSArray *)objects
{
    if (![objects count])
        return;
    [self _clearFilterForInsertion];
    NSUInteger n = [[self _contentObjects] count];
    [self _contentInsert:objects atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(n, [objects count])]];
    [self _insertedObjects:objects
         atArrangedIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange([_arranged count], [objects count])]];
}
- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index
{
    if (object)
        [self insertObjects:[NSArray arrayWithObject:object] atArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:index]];
}
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes
{
    if (![objects count] || [indexes count] != [objects count])
        return;
    [self _clearFilterForInsertion];
    if ([indexes lastIndex] >= [_arranged count] + [objects count])
        [NSException raise:NSRangeException format:@"-[NSArrayController insertObjects:atArrangedObjectIndexes:]: "
                                                    @"index %lu beyond bounds",
                                                    (unsigned long)[indexes lastIndex]];
    /* in the content, each goes before the arranged object it is put
     * before (or at the end), one at a time */
    NSMutableArray *after = [[_arranged mutableCopy] autorelease];
    [after insertObjects:objects atIndexes:indexes];
    NSUInteger n = 0;
    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound; i = [indexes indexGreaterThanIndex:i]) {
        NSArray *content = [self _contentObjects];
        NSUInteger at = [content count];
        for (NSUInteger j = i + 1; j < [after count]; j++) {
            NSUInteger c = [content indexOfObjectIdenticalTo:[after objectAtIndex:j]];
            if (c != NSNotFound) {
                at = c;
                break;
            }
        }
        [self _contentInsert:[NSArray arrayWithObject:[objects objectAtIndex:n++]] atIndexes:[NSIndexSet indexSetWithIndex:at]];
    }
    [self _insertedObjects:objects atArrangedIndexes:indexes];
}
/* Objects have left the content: the selection keeps those of the selected
 * objects that are left, or (avoidsEmptySelection) moves to the object
 * where the first removed one was. */
- (void)_removedObjects:(NSArray *)objects
{
    NSIndexSet *gone = indexes_of(objects, _arranged);
    NSArray *keep = [self selectedObjects];
    NSMutableArray *arranged = [[_arranged mutableCopy] autorelease];
    [arranged removeObjectsAtIndexes:gone];
    NSIndexSet *sel = indexes_of(keep, arranged);
    if (![sel count] && _avoidsEmpty && [arranged count])
        sel = [NSIndexSet indexSetWithIndex:MIN([gone count] ? [gone firstIndex] : 0, [arranged count] - 1)];
    [self _commitArranged:_autoRearranges ? [self arrangeObjects:[self _contentObjects]] : arranged selection:sel];
}
- (void)removeObject:(id)object
{
    if (object)
        [self removeObjects:[NSArray arrayWithObject:object]];
}
- (void)removeObjects:(NSArray *)objects
{
    if (![objects count])
        return;
    [self _contentRemove:objects];
    [self _removedObjects:objects];
}
- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)index
{
    [self removeObjectsAtArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:index]];
}
- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes
{
    if (![indexes count])
        return;
    [self removeObjects:[_arranged objectsAtIndexes:indexes]];
}
/* The actions: carried out on the run loop's next turn. */
- (void)insert:(id)sender { [self performSelector:@selector(_ferryInsert) withObject:nil afterDelay:0]; }
- (void)_ferryInsert
{
    id obj = [self newObject];
    NSUInteger at = [_selectionIndexes count] ? [_selectionIndexes firstIndex] : 0;
    [self insertObject:obj atArrangedObjectIndex:MIN(at, [_arranged count])];
    [obj release];
}
- (void)_ferryRemove { [self removeObjectsAtArrangedObjectIndexes:_selectionIndexes]; }

/* ---- bindings ---- */

- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentArrayBinding] || [binding isEqualToString:NSContentSetBinding] ||
        [binding isEqualToString:NSContentBinding]) {
        if (NSIsControllerMarker(value))
            value = nil;
        if (_editingContent)
            [self _takeContent:value];   /* our own change, arranged by us */
        else
            [self setContent:value];
    } else if ([binding isEqualToString:NSSelectionIndexesBinding]) {
        [self setSelectionIndexes:[value isKindOfClass:[NSIndexSet class]] ? value : [NSIndexSet indexSet]];
    } else if ([binding isEqualToString:NSSortDescriptorsBinding]) {
        NSArray *d = [value isKindOfClass:[NSArray class]] ? value : nil;
        if (!(d == _sortDescriptors || [d isEqual:_sortDescriptors]))
            [self setSortDescriptors:d];
    } else if ([binding isEqualToString:NSFilterPredicateBinding]) {
        NSPredicate *p = [value isKindOfClass:[NSPredicate class]] ? value : nil;
        if (p != _filterPredicate)
            [self setFilterPredicate:p];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentArrayBinding] || [binding isEqualToString:NSContentSetBinding] ||
        [binding isEqualToString:NSContentBinding])
        return _items;
    if ([binding isEqualToString:NSSelectionIndexesBinding])
        return [self selectionIndexes];
    if ([binding isEqualToString:NSSortDescriptorsBinding])
        return [self sortDescriptors];
    if ([binding isEqualToString:NSFilterPredicateBinding])
        return _filterPredicate;
    return [super _ferryValueForBinding:binding];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p: %lu arranged of %lu, selection %@>", [self class], self,
                                      (unsigned long)[_arranged count], (unsigned long)[[self _contentObjects] count],
                                      _selectionIndexes];
}
@end

/* ---- arrangedObjects ---- */

static char arranged_context;

@implementation AArrangedObjects
- (NSUInteger)count { return [[controller _arranged] count]; }
- (id)objectAtIndex:(NSUInteger)index { return [[controller _arranged] objectAtIndex:index]; }
/* key paths through us are followed onto the arranged objects */
- (BOOL)_ferryObservesElements { return YES; }
- (void)dealloc
{
    [self _contentWillChange];
    [_keys release];
    [super dealloc];
}
- (void)_watch:(NSString *)k
{
    for (id o in _watched)
        [o addObserver:self forKeyPath:k options:NSKeyValueObservingOptionPrior context:&arranged_context];
}
- (void)_unwatch:(NSString *)k
{
    for (id o in _watched)
        [o removeObserver:self forKeyPath:k context:&arranged_context];
}
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options
            context:(void *)context
{
    NSString *k = first_key(keyPath);
    if (![k hasPrefix:@"@"]) {
        if (!_keys)
            _keys = [[NSMutableDictionary alloc] init];
        NSUInteger n = [[_keys objectForKey:k] unsignedIntegerValue];
        if (!n) {
            if (!_watched)
                _watched = [distinct([controller _arranged]) copy];
            [self _watch:k];
        }
        [_keys setObject:@(n + 1) forKey:k];
    }
    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}
- (void)_forget:(NSString *)keyPath
{
    NSString *k = first_key(keyPath);
    NSUInteger n = [[_keys objectForKey:k] unsignedIntegerValue];
    if (!n)
        return;
    if (n > 1) {
        [_keys setObject:@(n - 1) forKey:k];
        return;
    }
    [_keys removeObjectForKey:k];
    [self _unwatch:k];
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    [super removeObserver:observer forKeyPath:keyPath];
    [self _forget:keyPath];
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    [super removeObserver:observer forKeyPath:keyPath context:context];
    [self _forget:keyPath];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context != &arranged_context) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue])
        [self willChangeValueForKey:keyPath];
    else
        [self didChangeValueForKey:keyPath];
}
- (void)_contentWillChange
{
    for (NSString *k in _keys)
        [self _unwatch:k];
    [_watched release];
    _watched = nil;
}
- (void)_contentDidChange
{
    [_watched release];
    _watched = [distinct([controller _arranged]) copy];
    for (NSString *k in _keys)
        [self _watch:k];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return NO; }
@end

/* ---- selection ---- */

@implementation AArraySelection
- (NSArray *)_sources { return controller ? distinct([controller selectedObjects]) : [NSArray array]; }
/* One value for all the selected objects, or a marker. */
static id shared_value(id controller, NSString *keyPath, BOOL isPath)
{
    NSArray *objects = [controller selectedObjects];
    if (![objects count])
        return NSNoSelectionMarker;
    if ([objects count] > 1 && [controller alwaysUsesMultipleValuesMarker])
        return NSMultipleValuesMarker;
    id first = nil;
    for (NSUInteger i = 0; i < [objects count]; i++) {
        id v;
        @try {
            v = isPath ? [[objects objectAtIndex:i] valueForKeyPath:keyPath]
                       : [[objects objectAtIndex:i] valueForKey:keyPath];
        } @catch (NSException *e) {
            if (![[e name] isEqualToString:NSUndefinedKeyException])
                @throw;
            return NSNotApplicableMarker;
        }
        if (i == 0)
            first = v;
        else if (!(v == first || [v isEqual:first]))
            return NSMultipleValuesMarker;
    }
    return first;
}
- (id)valueForKey:(NSString *)key { return shared_value(controller, key, NO); }
- (id)valueForKeyPath:(NSString *)keyPath { return shared_value(controller, keyPath, YES); }
- (void)setValue:(id)value forKey:(NSString *)key
{
    for (id o in [controller selectedObjects])
        [o setValue:value forKey:key];
}
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath
{
    for (id o in [controller selectedObjects])
        [o setValue:value forKeyPath:keyPath];
}
- (BOOL)_ferryIsKeyValueProxy { return YES; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<selection of %lu object(s)>", (unsigned long)[[controller selectedObjects] count]];
}
@end
