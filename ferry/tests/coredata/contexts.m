/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's contexts together (freemac 1.209, Ferry 0.35.0), on an
 * SQLite store: the will-save, did-save and objects-did-change
 * notifications and their keys; obtainPermanentIDsForObjects:; a child
 * context saving into its parent, and the parent saving to the store;
 * private-queue contexts working on their own threads with performBlock:
 * and performBlockAndWait:, many at once; a did-save notification merged
 * into another context with mergeChangesFromContextDidSaveNotification:;
 * automaticallyMergesChangesFromParent; and the merge policies when two
 * contexts change the same object. */
#import "people.h"
#include <pthread.h>

static NSString *keys(NSDictionary *info)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in [info.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@=%lu", k, (unsigned long)[info[k] count]]];
    return [parts componentsJoinedByString:@" "];
}

static int count_people(NSManagedObjectContext *moc, NSString *format)
{
    __block NSUInteger n = 0;
    [moc performBlockAndWait:^{
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        if (format)
            f.predicate = [NSPredicate predicateWithFormat:format];
        n = [moc countForFetchRequest:f error:NULL];
    }];
    return (int)n;
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_contexts"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"contexts.sqlite"]];
        NSManagedObjectContext *main = people_context(people_model(), NSSQLiteStoreType, url, nil);
        NSPersistentStoreCoordinator *psc = main.persistentStoreCoordinator;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        NSMutableArray *log = [NSMutableArray array];
        id o1 = [nc addObserverForName:NSManagedObjectContextWillSaveNotification object:main queue:nil
                            usingBlock:^(NSNotification *n) { [log addObject:[NSString stringWithFormat:@"will-save(%@)", keys(n.userInfo)]]; }];
        id o2 = [nc addObserverForName:NSManagedObjectContextDidSaveNotification object:main queue:nil
                            usingBlock:^(NSNotification *n) { [log addObject:[NSString stringWithFormat:@"did-save(%@)", keys(n.userInfo)]]; }];
        id o3 = [nc addObserverForName:NSManagedObjectContextObjectsDidChangeNotification object:main queue:nil
                            usingBlock:^(NSNotification *n) { [log addObject:[NSString stringWithFormat:@"changed(%@)", keys(n.userInfo)]]; }];
        printf("notification names: %s, %s, %s\n", NSManagedObjectContextWillSaveNotification.UTF8String,
               NSManagedObjectContextDidSaveNotification.UTF8String,
               NSManagedObjectContextObjectsDidChangeNotification.UTF8String);
        printf("keys: %s %s %s %s %s %s\n", NSInsertedObjectsKey.UTF8String, NSUpdatedObjectsKey.UTF8String,
               NSDeletedObjectsKey.UTF8String, NSRefreshedObjectsKey.UTF8String, NSInvalidatedObjectsKey.UTF8String,
               NSInvalidatedAllObjectsKey.UTF8String);

        Person *ann = new_person(main, @"Ann", 30);
        Person *bob = new_person(main, @"Bob", 40);
        [main processPendingChanges];
        NSError *error = nil;
        printf("obtain permanent IDs: %d, ann temporary %d, bob temporary %d\n",
               [main obtainPermanentIDsForObjects:@[ ann ] error:&error], ann.objectID.isTemporaryID,
               bob.objectID.isTemporaryID);
        [main save:&error];
        ann.age = 31;
        [main deleteObject:bob];
        [main processPendingChanges];
        [main save:&error];
        printf("notifications: %s\n", [[log componentsJoinedByString:@" "] UTF8String]);
        [nc removeObserver:o1];
        [nc removeObserver:o2];
        [nc removeObserver:o3];

        /* a child context saves into its parent */
        NSManagedObjectContext *child = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        child.parentContext = main;
        Person *annInChild = (Person *)[child existingObjectWithID:ann.objectID error:&error];
        annInChild.age = 32;
        Person *cy = new_person(child, @"Cy", 7);
        printf("child: parent is main %d, coordinator %d, has changes %d; main has changes %d\n",
               child.parentContext == main, child.persistentStoreCoordinator == psc, child.hasChanges, main.hasChanges);
        printf("child saved: %d; cy temporary %d\n", [child save:&error], cy.objectID.isTemporaryID);
        printf("main after the child's save: ann %d, people %d, has changes %d, store has %d\n", ann.age,
               count_people(main, nil), main.hasChanges, count_people(people_context(people_model(), NSSQLiteStoreType, url, nil), nil));
        printf("main saved: %d; store has %d\n", [main save:&error],
               count_people(people_context(people_model(), NSSQLiteStoreType, url, nil), nil));
        Person *cyInMain = (Person *)[main objectWithID:cy.objectID];
        printf("cy found in main by the child's ID: %s\n", str(cyInMain.name));

        /* private-queue contexts on their own threads */
        NSManagedObjectContext *bg = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        bg.persistentStoreCoordinator = psc;
        __block BOOL onMain = YES;
        __block NSDictionary *savedInfo = nil;
        id obs = [nc addObserverForName:NSManagedObjectContextDidSaveNotification object:bg queue:nil
                             usingBlock:^(NSNotification *n) {
                                 savedInfo = n.userInfo;
                                 [main performBlock:^{ [main mergeChangesFromContextDidSaveNotification:n]; }];
                             }];
        [bg performBlockAndWait:^{
            onMain = [NSThread isMainThread];
            for (int i = 0; i < 20; i++)
                new_person(bg, [NSString stringWithFormat:@"bg%02d", i], i);
            Person *a = (Person *)[bg existingObjectWithID:ann.objectID error:NULL];
            a.age = 33;
            [bg save:NULL];
        }];
        [nc removeObserver:obs];
        printf("performBlockAndWait: from the main thread runs there: %d; saved %s\n", onMain, str(keys(savedInfo)));
        for (int i = 0; i < 20 && ann.age != 33; i++)
            spin();
        printf("merged into main: ann %d, people %d\n", ann.age, count_people(main, nil));

        __block int done = 0, offMain = 0;
        NSLock *lock = [[NSLock alloc] init];
        NSMutableArray *contexts = [NSMutableArray array];
        for (int t = 0; t < 4; t++) {
            NSManagedObjectContext *c = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            c.persistentStoreCoordinator = psc;
            [contexts addObject:c];
            [c performBlock:^{
                for (int i = 0; i < 25; i++) {
                    new_person(c, [NSString stringWithFormat:@"t%d-%02d", t, i], 100 + t);
                    if (i % 5 == 4)
                        [c save:NULL];
                }
                [lock lock];
                done++;
                offMain += ![NSThread isMainThread];
                [lock unlock];
            }];
        }
        for (int i = 0; i < 500; i++) {
            [lock lock];
            int d = done;
            [lock unlock];
            if (d == 4)
                break;
            spin();
        }
        printf("four threads: done %d off the main thread %d, each saved 25: %d %d %d %d, all %d\n", done, offMain, count_people(main, @"age == 100"),
               count_people(main, @"age == 101"), count_people(main, @"age == 102"), count_people(main, @"age == 103"),
               count_people(main, nil));

        /* a child that follows its parent */
        NSManagedObjectContext *viewer = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        viewer.persistentStoreCoordinator = psc;
        viewer.automaticallyMergesChangesFromParent = YES;
        Person *annInViewer = (Person *)[viewer existingObjectWithID:ann.objectID error:&error];
        printf("viewer sees ann %d\n", annInViewer.age);
        NSManagedObjectContext *writer = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        writer.persistentStoreCoordinator = psc;
        [writer performBlockAndWait:^{
            Person *a = (Person *)[writer existingObjectWithID:ann.objectID error:NULL];
            a.age = 34;
            [writer save:NULL];
        }];
        for (int i = 0; i < 20 && annInViewer.age != 34; i++)
            spin();
        printf("viewer merged automatically: ann %d\n", annInViewer.age);
        NSManagedObjectContext *kid = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        kid.parentContext = viewer;
        kid.automaticallyMergesChangesFromParent = YES;
        Person *annInKid = (Person *)[kid existingObjectWithID:ann.objectID error:&error];
        annInViewer.age = 35;
        [viewer save:&error];
        for (int i = 0; i < 20 && annInKid.age != 35; i++)
            spin();
        printf("a child of the viewer follows it: ann %d\n", annInKid.age);

        /* conflicts */
        NSManagedObjectContext *a = people_context(people_model(), NSSQLiteStoreType, url, nil);
        NSManagedObjectContext *b = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        b.persistentStoreCoordinator = a.persistentStoreCoordinator;
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        f.predicate = [NSPredicate predicateWithFormat:@"name == 'Ann'"];
        NSArray *policies = @[ NSErrorMergePolicy, NSMergeByPropertyObjectTrumpMergePolicy,
                               NSMergeByPropertyStoreTrumpMergePolicy, NSOverwriteMergePolicy, NSRollbackMergePolicy ];
        NSArray *labels = @[ @"error", @"object trumps", @"store trumps", @"overwrite", @"rollback" ];
        for (NSUInteger i = 0; i < policies.count; i++) {
            Person *pa = [a executeFetchRequest:f error:NULL][0];
            Person *pb = [b executeFetchRequest:f error:NULL][0];
            [pa willAccessValueForKey:nil];
            [pb willAccessValueForKey:nil];
            pa.age = 50;
            pa.score = @1;
            [a save:NULL];
            pb.age = 60;
            pb.nickname = @"b";
            b.mergePolicy = policies[i];
            error = nil;
            BOOL ok = [b save:&error];
            [a refreshObject:pa mergeChanges:NO];
            printf("%-14s saved %d error %ld conflicts %lu; store has age %d score %s; b sees %d\n", [labels[i] UTF8String],
                   ok, (long)error.code, (unsigned long)[error.userInfo[NSPersistentStoreSaveConflictsErrorKey] count],
                   pa.age, str(pa.score), pb.age);
            [b rollback];
            [b refreshObject:pb mergeChanges:NO];
            pa.age = 1;
            pa.score = nil;
            [a save:NULL];
        }
    }
    return 0;
}
