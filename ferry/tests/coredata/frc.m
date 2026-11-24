/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSFetchedResultsController (freemac 1.209, Ferry 0.35.0): sections from
 * a key path with their names, index titles and objects, index paths both
 * ways, and the delegate's callbacks, in order, as objects are inserted,
 * updated, moved (by a change to the sort key or the section), deleted, and
 * as sections come and go; and a controller without a delegate, which
 * keeps the results it fetched. */
#import "people.h"

@interface Log : NSObject <NSFetchedResultsControllerDelegate>
@property (nonatomic, strong) NSMutableArray *lines;
@end

static NSString *ip(NSIndexPath *p) { return p ? [NSString stringWithFormat:@"%lu.%lu", (unsigned long)[p indexAtPosition:0], (unsigned long)[p indexAtPosition:1]] : @"-"; }

@implementation Log
- (instancetype)init
{
    if ((self = [super init]))
        _lines = [NSMutableArray array];
    return self;
}
- (void)controllerWillChangeContent:(NSFetchedResultsController *)c { [_lines addObject:@"will"]; }
- (void)controllerDidChangeContent:(NSFetchedResultsController *)c { [_lines addObject:@"did"]; }
- (void)controller:(NSFetchedResultsController *)c didChangeSection:(id<NSFetchedResultsSectionInfo>)s
           atIndex:(NSUInteger)i forChangeType:(NSFetchedResultsChangeType)t
{
    [_lines addObject:[NSString stringWithFormat:@"section %@ %@ at %lu", t == NSFetchedResultsChangeInsert ? @"insert" : @"delete",
                                                 s.name, (unsigned long)i]];
}
- (void)controller:(NSFetchedResultsController *)c didChangeObject:(id)o atIndexPath:(NSIndexPath *)from
     forChangeType:(NSFetchedResultsChangeType)t newIndexPath:(NSIndexPath *)to
{
    NSString *kind = @[ @"?", @"insert", @"delete", @"move", @"update" ][t];
    [_lines addObject:[NSString stringWithFormat:@"%@ %@ %@>%@", kind, [o name], ip(from), ip(to)]];
}
- (void)flush:(const char *)what
{
    printf("%-26s %s\n", what, [[_lines componentsJoinedByString:@", "] UTF8String]);
    [_lines removeAllObjects];
}
@end

static void sections(NSFetchedResultsController *c)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (id<NSFetchedResultsSectionInfo> s in c.sections)
        [parts addObject:[NSString stringWithFormat:@"%@[%@]:%@", s.name, s.indexTitle, names(s.objects)]];
    printf("  sections: %s\n", [[parts componentsJoinedByString:@" "] UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        NSManagedObjectContext *moc = people_context(people_model(), NSInMemoryStoreType, nil, nil);
        NSDictionary *who = @{ @"ann" : @"eng", @"bob" : @"eng", @"cy" : @"ops", @"dee" : @"ops", @"eve" : @"ops" };
        NSMutableDictionary *people = [NSMutableDictionary dictionary];
        int age = 20;
        for (NSString *n in [who.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            Person *p = new_person(moc, n, age += 5);
            p.nickname = who[n];
            p.home = [NSURL URLWithString:who[n]];
            people[n] = p;
        }
        NSError *error = nil;
        [moc save:&error];

        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        f.predicate = [NSPredicate predicateWithFormat:@"age < 100"];
        f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"home.absoluteString" ascending:YES],
                               [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ];
        NSFetchedResultsController *c = [[NSFetchedResultsController alloc] initWithFetchRequest:f
                                                                            managedObjectContext:moc
                                                                              sectionNameKeyPath:@"home.absoluteString"
                                                                                       cacheName:@"People"];
        Log *log = [[Log alloc] init];
        c.delegate = log;
        printf("performFetch: %d, %lu objects\n", [c performFetch:&error], (unsigned long)c.fetchedObjects.count);
        sections(c);
        printf("  index titles: %s\n", [[c.sectionIndexTitles componentsJoinedByString:@","] UTF8String]);
        NSUInteger idx[2] = {1, 2};
        NSIndexPath *p12 = [NSIndexPath indexPathWithIndexes:idx length:2];
        printf("  object at 1.2: %s; index path of bob: %s; section for title O: %ld\n", str([[c objectAtIndexPath:p12] name]),
               str(ip([c indexPathForObject:people[@"bob"]])), (long)[c sectionForSectionIndexTitle:@"O" atIndex:1]);

        Person *fay = new_person(moc, @"fay", 26);
        fay.home = [NSURL URLWithString:@"eng"];
        [moc processPendingChanges];
        [log flush:"insert fay:"];
        [people[@"ann"] setAge:99];
        [moc processPendingChanges];
        [log flush:"ann's age 99, a move:"];
        [people[@"ann"] setAge:31];
        [moc processPendingChanges];
        [log flush:"ann's age 31, no move:"];
        [people[@"bob"] setHome:[NSURL URLWithString:@"ops"]];
        [moc processPendingChanges];
        [log flush:"bob to ops:"];
        [people[@"cy"] setAge:150];
        [moc processPendingChanges];
        [log flush:"cy filtered out:"];
        [moc deleteObject:people[@"dee"]];
        [moc processPendingChanges];
        [log flush:"delete dee:"];
        Person *gus = new_person(moc, @"gus", 1);
        gus.home = [NSURL URLWithString:@"hr"];
        [moc processPendingChanges];
        [log flush:"gus in a new section:"];
        sections(c);
        [moc deleteObject:fay];
        [moc deleteObject:people[@"ann"]];
        [moc processPendingChanges];
        [log flush:"eng emptied:"];
        sections(c);
        [moc save:&error];
        [log flush:"save:"];
        [people[@"eve"] setName:@"eva"];
        [moc processPendingChanges];
        [log flush:"rename eve:"];

        c.delegate = nil;
        new_person(moc, @"hal", 2).home = [NSURL URLWithString:@"hr"];
        [moc processPendingChanges];
        printf("without a delegate: %lu objects kept\n", (unsigned long)c.fetchedObjects.count);
        [c performFetch:&error];
        printf("fetched again: %lu objects\n", (unsigned long)c.fetchedObjects.count);

        NSFetchRequest *g = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        g.predicate = [NSPredicate predicateWithFormat:@"age > 1000"];
        g.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
        NSFetchedResultsController *flat = [[NSFetchedResultsController alloc] initWithFetchRequest:g managedObjectContext:moc
                                                                                 sectionNameKeyPath:nil cacheName:nil];
        [flat performFetch:&error];
        printf("no key path and no objects: %lu section of %lu\n", (unsigned long)flat.sections.count,
               (unsigned long)[flat.sections[0] numberOfObjects]);
        NSFetchRequest *unsorted = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        NSFetchedResultsController *bad = [[NSFetchedResultsController alloc] initWithFetchRequest:unsorted
                                                                              managedObjectContext:moc
                                                                                sectionNameKeyPath:nil cacheName:nil];
        @try {
            [bad performFetch:&error];
            printf("no sort descriptors: fetched\n");
        } @catch (NSException *e) {
            printf("no sort descriptors: %s\n", str(e.name));
        }
    }
    return 0;
}
