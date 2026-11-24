/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSArrayController and NSObjectController in Core Data's entity mode
 * (freemac 1.209, Ferry 0.35.0), with no display: an entity name and a
 * managed object context, the content fetched when the controller prepares
 * it and by fetch: (on the run loop's next turn) and fetchWithRequest:
 * (at once), a fetch predicate, add: inserting a new object of the entity
 * into the context, remove: deleting the selected objects from it, objects
 * inserted into or deleted from the context by other code followed, and a
 * save of what the controller made. */
#import <Cocoa/Cocoa.h>
#import "people.h"

static void turn(void) { spin(); }

static void show(const char *what, NSArrayController *ac)
{
    printf("%-44s %s (selected %s)\n", what, names(ac.arrangedObjects).UTF8String,
           names(ac.selectedObjects).UTF8String);
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_array_controller"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"people.sqlite"]];
        NSManagedObjectContext *moc = people_context(people_model(), NSSQLiteStoreType, url, nil);
        new_person(moc, @"Ann", 30);
        new_person(moc, @"Bob", 45);
        new_person(moc, @"Cy", 52);
        Car *car = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        car.plate = @"K-1";
        NSError *error = nil;
        printf("saved: %d\n", [moc save:&error]);

        NSArrayController *ac = [[NSArrayController alloc] init];
        ac.entityName = @"Person";
        ac.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
        ac.automaticallyPreparesContent = YES;
        printf("before a context: content %s, newObject a mutable dictionary %d\n", str(ac.content),
               [[ac newObject] isKindOfClass:[NSMutableDictionary class]]);
        ac.managedObjectContext = moc;
        printf("context set: same context %d, content yet %s\n", ac.managedObjectContext == moc, str(ac.content));
        turn();
        show("fetched on the next turn:", ac);
        printf("content is a mutable array: %d\n", [ac.content isKindOfClass:[NSMutableArray class]]);

        ac.fetchPredicate = [NSPredicate predicateWithFormat:@"age > 40"];
        NSFetchRequest *def = [ac defaultFetchRequest];
        printf("default fetch request: %s where %s\n", str(def.entityName), str(def.predicate.predicateFormat));
        [ac fetch:nil];
        show("fetch: with a predicate, before the turn:", ac);
        turn();
        show("fetch: with a predicate, after it:", ac);

        /* add: inserts a new Person into the context and selects it */
        [ac add:nil];
        turn();
        Person *added = ac.selectedObjects.firstObject;
        printf("add: a %s, inserted %d, in the context's inserted objects %d, arranged %lu\n",
               added.entity.name.UTF8String, added.isInserted, [moc.insertedObjects containsObject:added],
               (unsigned long)[ac.arrangedObjects count]);
        added.name = @"Dee";
        added.age = 61;
        [ac rearrangeObjects];
        show("named Dee:", ac);

        /* others' changes to the context are followed */
        new_person(moc, @"Eve", 70);
        new_person(moc, @"Fay", 20);   /* doesn't match the predicate */
        Manager *gus = [NSEntityDescription insertNewObjectForEntityForName:@"Manager" inManagedObjectContext:moc];
        gus.name = @"Gus";
        gus.age = 55;
        Car *other = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        other.plate = @"K-2";
        [moc processPendingChanges];
        show("inserted elsewhere (Eve, Fay, Gus, a car):", ac);
        Person *bob = nil;
        for (Person *p in ac.arrangedObjects)
            if ([p.name isEqualToString:@"Bob"])
                bob = p;
        [moc deleteObject:bob];
        [moc processPendingChanges];
        show("Bob deleted elsewhere:", ac);

        /* remove: deletes the selection from the context */
        [ac setSelectionIndex:0];
        Person *removed = ac.selectedObjects.firstObject;
        [ac remove:nil];
        turn();
        printf("remove: %s, deleted %d\n", removed.name.UTF8String, removed.isDeleted);
        show("after remove:", ac);
        printf("saved: %d %s\n", [moc save:&error], str(error));

        /* what the store holds now */
        NSManagedObjectContext *fresh = people_context(people_model(), NSSQLiteStoreType, url, nil);
        NSFetchRequest *all = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        printf("in the store: %s\n", sorted_names([fresh executeFetchRequest:all error:&error]).UTF8String);

        /* fetchWithRequest:merge:error:, at once */
        NSArrayController *second = [[NSArrayController alloc] init];
        second.entityName = @"Person";
        second.managedObjectContext = fresh;
        NSFetchRequest *young = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        young.predicate = [NSPredicate predicateWithFormat:@"age < 50"];
        printf("fetchWithRequest: %d\n", [second fetchWithRequest:young merge:NO error:&error]);
        printf("  %s\n", sorted_names(second.arrangedObjects).UTF8String);
        young.predicate = [NSPredicate predicateWithFormat:@"name == 'Eve'"];
        [second fetchWithRequest:young merge:YES error:&error];
        printf("merged with Eve: %s\n", sorted_names(second.arrangedObjects).UTF8String);
        [second fetchWithRequest:young merge:NO error:&error];
        printf("replaced by Eve: %s\n", sorted_names(second.arrangedObjects).UTF8String);
        NSArrayController *none = [[NSArrayController alloc] init];
        none.entityName = @"Person";
        printf("no context: fetch %d\n", [none fetchWithRequest:nil merge:NO error:&error]);

        /* one object's controller */
        NSObjectController *oc = [[NSObjectController alloc] init];
        oc.entityName = @"Department";
        oc.managedObjectContext = fresh;
        Department *made = [oc newObject];
        printf("object controller's newObject: a %s, inserted %d\n", made.entity.name.UTF8String, made.isInserted);
        made.title = @"Ops";
        [oc prepareContent];
        turn();
        printf("its prepared content: %s\n", str([oc.content valueForKey:@"title"]));
        [oc remove:nil];
        turn();
        printf("remove: content %s, deleted %d\n", str(oc.content), made.isDeleted);
    }
    return 0;
}
