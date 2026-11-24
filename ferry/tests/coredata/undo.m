/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's undo and rollback (freemac 1.209, Ferry 0.35.0): an
 * attribute change, an insert, a delete with its cascade and nullify, and a
 * relationship change undone and redone through the context's
 * NSUndoManager, with undo groups closed by the run loop; changes made with
 * undo registration turned off; rollback, reset and refreshing an object
 * (merging its changes or not); and a context without an undo manager. */
#import "people.h"

static void state(const char *what, NSManagedObjectContext *moc)
{
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSMutableArray *parts = [NSMutableArray array];
    for (Person *p in [moc executeFetchRequest:f error:NULL])
        [parts addObject:[NSString stringWithFormat:@"%@/%d/%@/%@", p.name, p.age, p.department.title ?: @"-",
                                                    sorted_names(p.cars).length ? sorted_names(p.cars) : @"-"]];
    printf("%-28s %s; changes %d\n", what, [[parts componentsJoinedByString:@" "] UTF8String], moc.hasChanges);
}

int main(void)
{
    @autoreleasepool {
        NSManagedObjectContext *moc = people_context(people_model(), NSInMemoryStoreType, nil, nil);
        NSUndoManager *um = moc.undoManager;
        printf("undo manager: %d\n", um != nil);
        Department *eng = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
        eng.title = @"Eng";
        Person *ann = new_person(moc, @"Ann", 30);
        ann.department = eng;
        Car *car = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        car.plate = @"C-1";
        car.owner = ann;
        NSError *error = nil;
        [moc save:&error];
        spin();
        [um removeAllActions];
        state("saved:", moc);

        ann.age = 31;
        spin();
        ann.name = @"Anna";
        spin();
        state("two edits:", moc);
        printf("can undo %d, action name %s\n", um.canUndo, str(um.undoActionName));
        [um undo];
        state("undo:", moc);
        [um undo];
        state("undo:", moc);
        printf("can undo %d, can redo %d\n", um.canUndo, um.canRedo);
        [um redo];
        state("redo:", moc);
        [um undo];

        Person *bob = new_person(moc, @"Bob", 40);
        spin();
        state("insert:", moc);
        [um undo];
        printf("undone insert: bob inserted %d, context %d\n", bob.isInserted, bob.managedObjectContext != nil);
        state("", moc);
        [um redo];
        state("redo insert:", moc);
        [um undo];

        ann.department = nil;
        spin();
        state("nullify:", moc);
        printf("eng employees: %s\n", str(sorted_names(eng.employees)));
        [um undo];
        state("undo nullify:", moc);
        printf("eng employees: %s\n", str(sorted_names(eng.employees)));

        [moc deleteObject:ann];
        [moc processPendingChanges];
        spin();
        printf("deleted ann: car deleted %d (cascade), eng employees %s\n", car.isDeleted, str(sorted_names(eng.employees)));
        [um undo];
        printf("undone delete: ann deleted %d, car deleted %d, car owner %s, eng employees %s\n", ann.isDeleted,
               car.isDeleted, str(car.owner.name), str(sorted_names(eng.employees)));
        state("", moc);

        /* several changes in one group */
        [um beginUndoGrouping];
        ann.age = 50;
        Person *cy = new_person(moc, @"Cy", 5);
        cy.department = eng;
        [um endUndoGrouping];
        [um setActionName:@"Grouped"];
        state("grouped:", moc);
        printf("action name %s\n", str(um.undoActionName));
        [um undo];
        state("undo group:", moc);

        /* registration off: nothing to undo */
        [moc processPendingChanges];
        [um disableUndoRegistration];
        ann.age = 77;
        [moc processPendingChanges];
        [um enableUndoRegistration];
        printf("change without registration: age %d, can undo %d\n", ann.age, um.canUndo);

        /* rollback */
        ann.name = @"Changed";
        Person *dee = new_person(moc, @"Dee", 1);
        [moc deleteObject:car];
        state("before rollback:", moc);
        [moc rollback];
        state("rollback:", moc);
        printf("after rollback: dee context %d, car deleted %d, can undo %d\n", dee.managedObjectContext != nil,
               car.isDeleted, um.canUndo);

        /* refresh */
        ann.age = 99;
        ann.nickname = @"Nicky";
        [moc refreshObject:ann mergeChanges:YES];
        printf("refresh, merging: age %d, nickname %s, fault %d\n", ann.age, str(ann.nickname), ann.isFault);
        [moc refreshObject:ann mergeChanges:NO];
        printf("refresh, not merging: fault %d, age %d, changes %d\n", ann.isFault == YES, ann.age, moc.hasChanges);

        /* reset */
        NSManagedObjectID *annID = ann.objectID;
        [moc reset];
        printf("reset: registered %lu, ann context %d\n", (unsigned long)moc.registeredObjects.count,
               ann.managedObjectContext != nil);
        Person *again = (Person *)[moc existingObjectWithID:annID error:&error];
        printf("ann again: %s, a new object %d\n", str(again.name), again != ann);

        /* no undo manager */
        moc.undoManager = nil;
        again.age = 3;
        printf("without an undo manager: age %d, rollback works ", again.age);
        [moc rollback];
        printf("%d\n", again.age == 30);
    }
    return 0;
}
