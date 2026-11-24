/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's fetching (freemac 1.209, Ferry 0.35.0), from an SQLite store
 * and from an in-memory one, which must answer alike: predicates that the
 * SQLite store puts in SQL (comparisons, strings, BETWEEN, IN, nil, to-one
 * relationships, SELF, AND, OR and NOT) and ones it leaves to the context
 * (key paths through relationships, ANY, case-insensitive comparisons,
 * a block), sorting, limits and offsets, subentities, results as objects,
 * object IDs, dictionaries (with propertiesToFetch) and counts,
 * countForFetchRequest:, unsaved changes included or not, faults or not,
 * and the batch size and prefetching accepted. */
#import "people.h"

static NSArray *fetch(NSManagedObjectContext *moc, NSString *entity, NSPredicate *p, NSArray *sorts)
{
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:entity];
    f.predicate = p;
    f.sortDescriptors = sorts ?: @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSError *error = nil;
    NSArray *r = [moc executeFetchRequest:f error:&error];
    if (!r)
        printf("fetch failed: %s\n", str(error));
    return r;
}

static void q(NSManagedObjectContext *moc, NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSPredicate *p = [NSPredicate predicateWithFormat:format arguments:ap];
    va_end(ap);
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.predicate = p;
    NSUInteger n = [moc countForFetchRequest:f error:NULL];
    printf("  %-44s %s (%lu)\n", format.UTF8String, str(names(fetch(moc, @"Person", p, nil))), (unsigned long)n);
}

static void fill(NSManagedObjectContext *moc)
{
    Department *eng = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
    eng.title = @"Eng";
    Department *ops = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
    ops.title = @"Ops";
    NSArray *rows = @[ @[ @"Ann", @41, @3.5, @"Eng" ], @[ @"bob", @29, @1.0, @"Ops" ], @[ @"Cyd", @35, [NSNull null], @"Eng" ],
                       @[ @"Dee", @29, @2.0, [NSNull null] ], @[ @"Éva", @52, @4.5, @"Ops" ], @[ @"Fay", @18, @0.5, @"Eng" ] ];
    int i = 0;
    for (NSArray *r in rows) {
        Person *p = new_person(moc, r[0], [r[1] intValue]);
        if (r[2] != [NSNull null])
            p.score = r[2];
        p.born = [NSDate dateWithTimeIntervalSinceReferenceDate:1000.0 * i++];
        p.active = (i % 2) == 1;
        p.department = [r[3] isEqual:@"Eng"] ? eng : [r[3] isEqual:@"Ops"] ? ops : nil;
        Car *c = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        c.plate = [NSString stringWithFormat:@"%@-%d", [r[0] substringToIndex:1], i];
        c.owner = p;
    }
    Manager *m = [NSEntityDescription insertNewObjectForEntityForName:@"Manager" inManagedObjectContext:moc];
    m.name = @"Max";
    m.age = 60;
    m.level = 2;
    m.department = ops;
}

static void run(NSManagedObjectContext *moc)
{
    NSError *error = nil;
    Department *eng = fetch(moc, @"Department", [NSPredicate predicateWithFormat:@"title == 'Eng'"],
                            @[ [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES] ])[0];
    Person *ann = fetch(moc, @"Person", [NSPredicate predicateWithFormat:@"name == 'Ann'"], nil)[0];
    NSDate *mid = [NSDate dateWithTimeIntervalSinceReferenceDate:2500];
    printf(" predicates:\n");
    q(moc, @"age == 29");
    q(moc, @"age != 29");
    q(moc, @"age > 30 AND age <= 52");
    q(moc, @"age < 20 OR age >= 60");
    q(moc, @"NOT (age BETWEEN {20, 40})");
    q(moc, @"age IN {18, 41, 99}");
    q(moc, @"score == nil");
    q(moc, @"score != nil AND score < 2.5");
    q(moc, @"born > %@", mid);
    q(moc, @"name BEGINSWITH 'D' OR name ENDSWITH 'y'");
    q(moc, @"name CONTAINS 'v'");
    q(moc, @"name LIKE '?a*'");
    q(moc, @"name BEGINSWITH[c] 'b'");
    q(moc, @"name ==[cd] 'eva'");
    q(moc, @"name CONTAINS[c] 'A'");
    q(moc, @"active == YES");
    q(moc, @"department == %@", eng);
    q(moc, @"department == %@", eng.objectID);
    q(moc, @"department != %@", eng);
    q(moc, @"department == nil");
    q(moc, @"department.title == 'Ops'");
    q(moc, @"ANY cars.plate BEGINSWITH 'F'");
    q(moc, @"SELF == %@", ann);
    q(moc, @"SELF IN %@", @[ ann.objectID, eng.objectID ]);
    q(moc, @"TRUEPREDICATE");
    q(moc, @"FALSEPREDICATE");
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.predicate = [NSPredicate predicateWithBlock:^BOOL(Person *p, NSDictionary *b) { return p.name.length == 3 && p.age < 30; }];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    printf("  a block predicate: %s\n", str(names([moc executeFetchRequest:f error:&error])));

    printf(" sorting and limits:\n");
    NSArray *byAge = @[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:NO],
                        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    printf("  by age down, name up: %s\n", str(names(fetch(moc, @"Person", nil, byAge))));
    printf("  by score (nil first): %s\n",
           str(names(fetch(moc, @"Person", nil, @[ [NSSortDescriptor sortDescriptorWithKey:@"score" ascending:YES] ]))));
    printf("  by name, case-insensitive: %s\n",
           str(names(fetch(moc, @"Person", nil,
                           @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                             selector:@selector(caseInsensitiveCompare:)] ]))));
    printf("  by department title: %s\n",
           str(names(fetch(moc, @"Person", [NSPredicate predicateWithFormat:@"department != nil"],
                           @[ [NSSortDescriptor sortDescriptorWithKey:@"department.title" ascending:NO],
                              [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]))));
    f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.sortDescriptors = byAge;
    f.fetchLimit = 3;
    printf("  limit 3: %s\n", str(names([moc executeFetchRequest:f error:&error])));
    f.fetchOffset = 2;
    printf("  limit 3 offset 2: %s, count %lu\n", str(names([moc executeFetchRequest:f error:&error])),
           (unsigned long)[moc countForFetchRequest:f error:&error]);
    f.fetchLimit = 0;
    f.fetchOffset = 5;
    printf("  offset 5: %s\n", str(names([moc executeFetchRequest:f error:&error])));
    f.fetchOffset = 0;
    f.fetchLimit = 2;
    f.predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] 'a'"];
    printf("  limit 2 of an in-memory predicate: %s\n", str(names([moc executeFetchRequest:f error:&error])));
    f.fetchLimit = 0;
    f.predicate = nil;

    printf(" entities:\n");
    printf("  managers: %s\n", str(names(fetch(moc, @"Manager", nil, nil))));
    f.includesSubentities = NO;
    printf("  people without subentities: %lu\n", (unsigned long)[moc countForFetchRequest:f error:&error]);
    f.includesSubentities = YES;
    printf("  people with subentities: %lu\n", (unsigned long)[moc countForFetchRequest:f error:&error]);

    printf(" result types:\n");
    f.resultType = NSManagedObjectIDResultType;
    NSArray *ids = [moc executeFetchRequest:f error:&error];
    printf("  IDs: %lu, first is an ID %d\n", (unsigned long)ids.count, [ids[0] isKindOfClass:[NSManagedObjectID class]]);
    f.resultType = NSCountResultType;
    NSArray *counted = [moc executeFetchRequest:f error:&error];
    printf("  count: %lu result, %s\n", (unsigned long)counted.count, str(counted.firstObject));
    f.resultType = NSDictionaryResultType;
    f.propertiesToFetch = @[ @"name", @"age", @"department" ];
    f.predicate = [NSPredicate predicateWithFormat:@"age < 30"];
    for (NSDictionary *d in [moc executeFetchRequest:f error:&error])
        printf("  dictionary: %s %s department %s\n", str(d[@"name"]), str(d[@"age"]),
               d[@"department"] ? ([d[@"department"] isKindOfClass:[NSManagedObjectID class]] ? "an ID" : "other") : "none");
    f.propertiesToFetch = @[ @"age" ];
    f.returnsDistinctResults = YES;
    f.predicate = nil;
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ];
    NSMutableArray *ages = [NSMutableArray array];
    for (NSDictionary *d in [moc executeFetchRequest:f error:&error])
        [ages addObject:d[@"age"]];
    printf("  distinct ages: %s\n", [[ages componentsJoinedByString:@","] UTF8String]);

    printf(" pending changes:\n");
    Person *gus = new_person(moc, @"Gus", 29);
    ann.age = 29;
    Person *bob = fetch(moc, @"Person", [NSPredicate predicateWithFormat:@"name == 'bob'"], nil)[0];
    [moc deleteObject:bob];
    f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.predicate = [NSPredicate predicateWithFormat:@"age == 29"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    printf("  age 29, unsaved included: %s (%lu)\n", str(names([moc executeFetchRequest:f error:&error])),
           (unsigned long)[moc countForFetchRequest:f error:&error]);
    f.fetchLimit = 1;
    printf("  the same, limit 1: %s\n", str(names([moc executeFetchRequest:f error:&error])));
    f.fetchLimit = 0;
    f.includesPendingChanges = NO;
    f.resultType = NSManagedObjectIDResultType;
    printf("  age 29 as stored: %lu IDs\n", (unsigned long)[[moc executeFetchRequest:f error:&error] count]);
    [moc rollback];
    printf("  after rollback, gus deleted %d, ann %d\n", gus.managedObjectContext == nil, ann.age);

    printf(" faults:\n");
    [moc reset];
    f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.predicate = [NSPredicate predicateWithFormat:@"age > 40"];
    f.fetchBatchSize = 2;
    f.relationshipKeyPathsForPrefetching = @[ @"department" ];
    NSArray *r = [moc executeFetchRequest:f error:&error];
    printf("  %lu fetched as faults: %d\n", (unsigned long)r.count, [r[0] isFault]);
    f.returnsObjectsAsFaults = NO;
    [moc reset];
    r = [moc executeFetchRequest:f error:&error];
    printf("  %lu fetched filled: %d\n", (unsigned long)r.count, ![r[0] isFault]);
    NSManagedObject *o = [moc objectWithID:[r[0] objectID]];
    printf("  objectWithID: same object %d; existingObjectWithID: %d\n", o == r[0],
           [moc existingObjectWithID:[r[0] objectID] error:&error] == r[0]);
    NSFetchRequest *bad = [NSFetchRequest fetchRequestWithEntityName:@"Nobody"];
    @try {
        [moc executeFetchRequest:bad error:&error];
        printf("  an unknown entity: no exception\n");
    } @catch (NSException *e) {
        printf("  an unknown entity: %s\n", str(e.name));
    }
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_fetch"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"fetch.sqlite"]];
        NSManagedObjectModel *model = people_model();
        for (NSString *type in @[ NSSQLiteStoreType, NSInMemoryStoreType ]) {
            printf("%s store:\n", type.UTF8String);
            NSManagedObjectContext *moc = people_context(model, type, [type isEqual:NSSQLiteStoreType] ? url : nil, nil);
            fill(moc);
            NSError *error = nil;
            if (![moc save:&error])
                printf("save failed: %s\n", str(error));
            [moc reset];
            run(moc);
        }
    }
    return 0;
}
