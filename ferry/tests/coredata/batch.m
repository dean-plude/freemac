/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's batch requests on an SQLite store (freemac 1.209, Ferry
 * 0.35.0): NSBatchUpdateRequest with a predicate, its three result types,
 * and objects in a context that don't change until they are refreshed or
 * the IDs are merged with mergeChangesFromRemoteContextSave:intoContexts:;
 * NSBatchDeleteRequest by fetch request and by object IDs, with the
 * cascade and nullify rules applied to the rows and the deny rule
 * refusing; and both refused on an in-memory store. */
#import "people.h"

static NSString *stored(NSManagedObjectContext *moc)
{
    NSManagedObjectContext *fresh = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    fresh.persistentStoreCoordinator = moc.persistentStoreCoordinator;
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSMutableArray *parts = [NSMutableArray array];
    for (Person *p in [fresh executeFetchRequest:f error:NULL])
        [parts addObject:[NSString stringWithFormat:@"%@/%d/%d/%@", p.name, p.age, p.active, p.department.title ?: @"-"]];
    f = [NSFetchRequest fetchRequestWithEntityName:@"Car"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"plate" ascending:YES] ];
    for (Car *c in [fresh executeFetchRequest:f error:NULL])
        [parts addObject:[NSString stringWithFormat:@"%@(%@)", c.plate, c.owner.name ?: @"-"]];
    return [parts componentsJoinedByString:@" "];
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_batch"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"batch.sqlite"]];
        NSManagedObjectContext *moc = people_context(people_model(), NSSQLiteStoreType, url, nil);
        Department *eng = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
        eng.title = @"Eng";
        NSMutableArray *people = [NSMutableArray array];
        for (int i = 0; i < 6; i++) {
            Person *p = new_person(moc, [NSString stringWithFormat:@"p%d", i], 20 + i);
            p.active = YES;
            if (i < 3)
                p.department = eng;
            Car *c = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
            c.plate = [NSString stringWithFormat:@"c%d", i];
            c.owner = p;
            [people addObject:p];
        }
        NSError *error = nil;
        [moc save:&error];
        printf("stored: %s\n", stored(moc).UTF8String);

        NSBatchUpdateRequest *u = [NSBatchUpdateRequest batchUpdateRequestWithEntityName:@"Person"];
        u.predicate = [NSPredicate predicateWithFormat:@"age >= 23"];
        u.propertiesToUpdate = @{ @"active" : @NO, @"age" : @99 };
        u.resultType = NSUpdatedObjectIDsResultType;
        NSBatchUpdateResult *ur = (NSBatchUpdateResult *)[moc executeRequest:u error:&error];
        NSArray *ids = ur.result;
        printf("batch update: %lu IDs (%s)\n", (unsigned long)ids.count, str(error));
        printf("stored: %s\n", stored(moc).UTF8String);
        Person *p3 = people[3];
        printf("p3 in the context before merging: age %d\n", p3.age);
        [NSManagedObjectContext mergeChangesFromRemoteContextSave:@{ NSUpdatedObjectsKey : ids } intoContexts:@[ moc ]];
        printf("p3 after merging the IDs: age %d active %d\n", p3.age, p3.active);
        u.resultType = NSUpdatedObjectsCountResultType;
        u.propertiesToUpdate = @{ @"age" : @50 };
        u.predicate = [NSPredicate predicateWithFormat:@"age == 99"];
        printf("count result: %s\n", str([(NSBatchUpdateResult *)[moc executeRequest:u error:&error] result]));
        u.resultType = NSStatusOnlyResultType;
        u.predicate = [NSPredicate predicateWithFormat:@"name == 'p0'"];
        printf("status result: %s\n", str([(NSBatchUpdateResult *)[moc executeRequest:u error:&error] result]));
        u.propertiesToUpdate = @{ @"cars" : @[] };
        error = nil;
        printf("a relationship can't be batch-updated: %d, error %ld\n", [moc executeRequest:u error:&error] != nil,
               (long)error.code);
        [moc refreshObject:people[0] mergeChanges:NO];
        printf("p0 refreshed: age %d\n", [people[0] age]);

        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        f.predicate = [NSPredicate predicateWithFormat:@"age == 50 AND name != 'p5'"];
        NSBatchDeleteRequest *d = [[NSBatchDeleteRequest alloc] initWithFetchRequest:f];
        d.resultType = NSBatchDeleteResultTypeObjectIDs;
        NSBatchDeleteResult *dr = (NSBatchDeleteResult *)[moc executeRequest:d error:&error];
        printf("batch delete by fetch: %lu IDs deleted, with their cars\n", (unsigned long)[dr.result count]);
        printf("stored: %s\n", stored(moc).UTF8String);
        [NSManagedObjectContext mergeChangesFromRemoteContextSave:@{ NSDeletedObjectsKey : dr.result } intoContexts:@[ moc ]];
        printf("p3 after merging the deletes: context %d\n", p3.managedObjectContext != nil);

        NSBatchDeleteRequest *byID = [[NSBatchDeleteRequest alloc] initWithObjectIDs:@[ [people[1] objectID] ]];
        byID.resultType = NSBatchDeleteResultTypeCount;
        printf("batch delete by ID: %s deleted, with its car\n", str([(NSBatchDeleteResult *)[moc executeRequest:byID error:&error] result]));
        printf("stored: %s\n", stored(moc).UTF8String);

        NSBatchDeleteRequest *dept = [[NSBatchDeleteRequest alloc]
            initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Department"]];
        error = nil;
        printf("deleting a department that has employees (deny): %d, error %ld\n",
               [moc executeRequest:dept error:&error] != nil, (long)error.code);
        NSBatchDeleteRequest *cars = [[NSBatchDeleteRequest alloc]
            initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Car"]];
        printf("p2's cars before: %lu\n", (unsigned long)[people[2] cars].count);
        printf("deleting every car: %d\n", [moc executeRequest:cars error:&error] != nil);
        printf("stored: %s\n", stored(moc).UTF8String);
        [moc refreshObject:people[2] mergeChanges:NO];
        printf("p2's cars after a refresh: %lu\n", (unsigned long)[people[2] cars].count);

        NSManagedObjectContext *mem = people_context(people_model(), NSInMemoryStoreType, nil, nil);
        error = nil;
        printf("on an in-memory store: %d, error %ld\n", [mem executeRequest:cars error:&error] != nil, (long)error.code);
    }
    return 0;
}
