/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: NSFetchedResultsController, as Apple's class reference
 * describes it (freemac 1.NEXT, Ferry 0.NEXT). Our own code; no Apple code
 * was used.
 *
 * With a delegate, the controller fetches again each time its context says
 * its objects changed, compares the new results with the old ones, and
 * tells the delegate what changed: will-change, then the sections deleted
 * and inserted, then the objects deleted, inserted, moved and updated, then
 * did-change. An object that changed is a move when its place among the
 * objects in both results changed (or its section did), and an update
 * otherwise; objects that only shifted because others came or went aren't
 * reported. Without a delegate the results stay as fetched. Nothing is
 * cached on disk. */
#import "CDInternal.h"

@interface CDSectionInfo : NSObject <NSFetchedResultsSectionInfo> {
@public
    NSString *_name, *_indexTitle;
    NSMutableArray *_objects;
}
@end

@implementation CDSectionInfo
- (void)dealloc
{
    [_name release];
    [_indexTitle release];
    [_objects release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (NSString *)indexTitle { return _indexTitle; }
- (NSUInteger)numberOfObjects { return [_objects count]; }
- (NSArray *)objects { return [[_objects copy] autorelease]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSFetchedResultsSectionInfo: name %@, %lu objects>", _name,
                                      (unsigned long)[_objects count]];
}
@end

@implementation NSFetchedResultsController {
    NSFetchRequest *_request;
    NSManagedObjectContext *_context;
    NSString *_sectionKeyPath, *_cacheName;
    id<NSFetchedResultsControllerDelegate> _delegate;   /* not retained */
    NSArray *_objects;
    NSArray *_sections;
    BOOL _observing, _updating;
}

- (instancetype)initWithFetchRequest:(NSFetchRequest *)request
                managedObjectContext:(NSManagedObjectContext *)context
                  sectionNameKeyPath:(NSString *)sectionNameKeyPath
                           cacheName:(NSString *)name
{
    if (!request || !context)
        CDRaise(NSInvalidArgumentException, @"An NSFetchedResultsController needs a fetch request and a context");
    if ((self = [super init])) {
        _request = [request retain];
        _context = [context retain];
        _sectionKeyPath = [sectionNameKeyPath copy];
        _cacheName = [name copy];
    }
    return self;
}

- (void)dealloc
{
    if (_observing)
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_request release];
    [_context release];
    [_sectionKeyPath release];
    [_cacheName release];
    [_objects release];
    [_sections release];
    [super dealloc];
}

+ (void)deleteCacheWithName:(NSString *)name {}
- (NSFetchRequest *)fetchRequest { return _request; }
- (NSManagedObjectContext *)managedObjectContext { return _context; }
- (NSString *)sectionNameKeyPath { return _sectionKeyPath; }
- (NSString *)cacheName { return _cacheName; }
- (id<NSFetchedResultsControllerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSFetchedResultsControllerDelegate>)delegate { _delegate = delegate; }
- (NSArray *)fetchedObjects { return _objects; }
- (NSArray *)sections { return _sections; }

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName
{
    if (![sectionName length])
        return @"";
    unichar c = [sectionName characterAtIndex:0];
    NSUInteger n = c >= 0xd800 && c <= 0xdbff && [sectionName length] > 1 ? 2 : 1;
    return [[sectionName substringToIndex:n] uppercaseString];
}

- (NSString *)cd_indexTitleFor:(NSString *)name
{
    if ([_delegate respondsToSelector:@selector(controller:sectionIndexTitleForSectionName:)])
        return [_delegate controller:self sectionIndexTitleForSectionName:name];
    return [self sectionIndexTitleForSectionName:name];
}

- (NSString *)cd_sectionNameFor:(id)object
{
    id v = [object valueForKeyPath:_sectionKeyPath];
    if (!v || v == [NSNull null])
        return @"";
    return [v isKindOfClass:[NSString class]] ? v : [v description];
}

- (NSArray *)cd_sectionsFor:(NSArray *)objects
{
    NSMutableArray *sections = [NSMutableArray array];
    CDSectionInfo *cur = nil;
    for (id o in objects) {
        NSString *name = _sectionKeyPath ? [self cd_sectionNameFor:o] : @"";
        if (!cur || ![cur->_name isEqualToString:name]) {
            cur = [[[CDSectionInfo alloc] init] autorelease];
            cur->_name = [name copy];
            cur->_indexTitle = [[self cd_indexTitleFor:name] copy];
            cur->_objects = [[NSMutableArray alloc] init];
            [sections addObject:cur];
        }
        [cur->_objects addObject:o];
    }
    if (!_sectionKeyPath && ![sections count]) {
        cur = [[[CDSectionInfo alloc] init] autorelease];
        cur->_name = @"";
        cur->_indexTitle = @"";
        cur->_objects = [[NSMutableArray alloc] init];
        [sections addObject:cur];
    }
    return sections;
}

- (BOOL)performFetch:(NSError **)error
{
    if (![[_request sortDescriptors] count])
        CDRaise(NSInvalidArgumentException, @"An instance of NSFetchedResultsController requires a fetch request with "
                                             @"sort descriptors");
    __block NSArray *objects = nil;
    __block NSError *err = nil;
    [_context cd_performAndWait:^{
        objects = [[_context executeFetchRequest:_request error:&err] retain];
        [err retain];
    }];
    [objects autorelease];
    [err autorelease];
    if (!objects) {
        if (error)
            *error = err;
        return NO;
    }
    [_objects release];
    _objects = [objects copy];
    [_sections release];
    _sections = [[self cd_sectionsFor:_objects] copy];
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cd_contextChanged:)
                                                     name:NSManagedObjectContextObjectsDidChangeNotification
                                                   object:_context];
    }
    return YES;
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger s = [indexPath indexAtPosition:0], i = [indexPath indexAtPosition:1];
    if (s >= [_sections count] || i >= [[[_sections objectAtIndex:s] objects] count])
        CDRaise(NSRangeException, @"no object at index %lu in section at index %lu", (unsigned long)i, (unsigned long)s);
    return [[[_sections objectAtIndex:s] objects] objectAtIndex:i];
}

static NSIndexPath *index_path(NSUInteger section, NSUInteger item)
{
    NSUInteger idx[2] = {section, item};
    return [NSIndexPath indexPathWithIndexes:idx length:2];
}

static NSIndexPath *find_in(NSArray *sections, id object)
{
    for (NSUInteger s = 0; s < [sections count]; s++) {
        NSUInteger i = [((CDSectionInfo *)[sections objectAtIndex:s])->_objects indexOfObjectIdenticalTo:object];
        if (i != NSNotFound)
            return index_path(s, i);
    }
    return nil;
}

- (NSIndexPath *)indexPathForObject:(id)object { return find_in(_sections, object); }

- (NSArray *)sectionIndexTitles
{
    NSMutableArray *titles = [NSMutableArray array];
    for (CDSectionInfo *s in _sections)
        if (s->_indexTitle && ![titles containsObject:s->_indexTitle])
            [titles addObject:s->_indexTitle];
    return titles;
}

- (NSInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)sectionIndex
{
    for (NSUInteger s = 0; s < [_sections count]; s++)
        if ([((CDSectionInfo *)[_sections objectAtIndex:s])->_indexTitle isEqualToString:title])
            return (NSInteger)s;
    CDRaise(NSInternalInconsistencyException, @"Index title at %ld is not equal to %@", (long)sectionIndex, title);
}

/* ---- following the context ---- */

- (void)cd_contextChanged:(NSNotification *)note
{
    if (!_delegate || _updating)
        return;
    _updating = YES;
    NSError *err = nil;
    NSArray *now = [_context executeFetchRequest:_request error:&err];
    if (!now) {
        _updating = NO;
        return;
    }
    NSDictionary *info = [note userInfo];
    NSMutableSet *changed = [NSMutableSet setWithSet:[info objectForKey:NSUpdatedObjectsKey] ?: [NSSet set]];
    [changed unionSet:[info objectForKey:NSRefreshedObjectsKey] ?: [NSSet set]];
    NSArray *oldSections = [[_sections retain] autorelease], *old = [[_objects retain] autorelease];
    NSArray *newSections = [self cd_sectionsFor:now];

    NSMutableArray *sectionDeletes = [NSMutableArray array], *sectionInserts = [NSMutableArray array];
    NSArray *oldNames = [oldSections valueForKey:@"name"], *newNames = [newSections valueForKey:@"name"];
    if (_sectionKeyPath) {
        for (NSUInteger s = 0; s < [oldSections count]; s++)
            if (![newNames containsObject:[oldNames objectAtIndex:s]])
                [sectionDeletes addObject:@(s)];
        for (NSUInteger s = 0; s < [newSections count]; s++)
            if (![oldNames containsObject:[newNames objectAtIndex:s]])
                [sectionInserts addObject:@(s)];
    }

    NSMutableArray *deletes = [NSMutableArray array], *inserts = [NSMutableArray array];
    NSMutableArray *moves = [NSMutableArray array], *updates = [NSMutableArray array];
    NSMutableArray *oldCommon = [NSMutableArray array], *newCommon = [NSMutableArray array];
    for (id o in old) {
        if ([now indexOfObjectIdenticalTo:o] == NSNotFound)
            [deletes addObject:o];
        else
            [oldCommon addObject:o];
    }
    for (id o in now) {
        if ([old indexOfObjectIdenticalTo:o] == NSNotFound)
            [inserts addObject:o];
        else
            [newCommon addObject:o];
    }
    for (id o in newCommon) {
        if (![changed containsObject:o])
            continue;
        NSIndexPath *from = find_in(oldSections, o), *to = find_in(newSections, o);
        BOOL sectionChanged = ![[oldNames objectAtIndex:[from indexAtPosition:0]]
            isEqual:[newNames objectAtIndex:[to indexAtPosition:0]]];
        if (sectionChanged || [oldCommon indexOfObjectIdenticalTo:o] != [newCommon indexOfObjectIdenticalTo:o])
            [moves addObject:o];
        else
            [updates addObject:o];
    }

    BOOL any = [sectionDeletes count] || [sectionInserts count] || [deletes count] || [inserts count] ||
               [moves count] || [updates count];
    [_objects release];
    _objects = [now copy];
    [_sections release];
    _sections = [newSections copy];
    if (any) {
        id<NSFetchedResultsControllerDelegate> d = _delegate;
        if ([d respondsToSelector:@selector(controllerWillChangeContent:)])
            [d controllerWillChangeContent:self];
        if ([d respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)]) {
            for (NSNumber *s in sectionDeletes)
                [d controller:self
                    didChangeSection:[oldSections objectAtIndex:[s unsignedIntegerValue]]
                             atIndex:[s unsignedIntegerValue]
                       forChangeType:NSFetchedResultsChangeDelete];
            for (NSNumber *s in sectionInserts)
                [d controller:self
                    didChangeSection:[newSections objectAtIndex:[s unsignedIntegerValue]]
                             atIndex:[s unsignedIntegerValue]
                       forChangeType:NSFetchedResultsChangeInsert];
        }
        if ([d respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]) {
            for (id o in deletes)
                [d controller:self
                    didChangeObject:o
                        atIndexPath:find_in(oldSections, o)
                      forChangeType:NSFetchedResultsChangeDelete
                       newIndexPath:nil];
            for (id o in inserts)
                [d controller:self
                    didChangeObject:o
                        atIndexPath:nil
                      forChangeType:NSFetchedResultsChangeInsert
                       newIndexPath:find_in(newSections, o)];
            for (id o in moves)
                [d controller:self
                    didChangeObject:o
                        atIndexPath:find_in(oldSections, o)
                      forChangeType:NSFetchedResultsChangeMove
                       newIndexPath:find_in(newSections, o)];
            for (id o in updates)
                [d controller:self
                    didChangeObject:o
                        atIndexPath:find_in(oldSections, o)
                      forChangeType:NSFetchedResultsChangeUpdate
                       newIndexPath:nil];
        }
        if ([d respondsToSelector:@selector(controllerDidChangeContent:)])
            [d controllerDidChangeContent:self];
    }
    _updating = NO;
}
@end
