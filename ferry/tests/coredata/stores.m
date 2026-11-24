/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's stores (freemac 1.209, Ferry 0.35.0): the SQLite store
 * (through the host's sqlite3) and the binary store, each saved and read
 * again by a second coordinator, with every attribute type, to-one, to-many
 * and ordered relationships, inheritance, faults and object IDs; the
 * in-memory store; store metadata, read and set; a store's URI
 * representations; NSPersistentContainer with a store description; and
 * opening a file that isn't a store. HOME and TMPDIR are the test's own. */
#import "people.h"
#include <stdlib.h>

static NSURL *file(NSString *name)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_stores"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return [NSURL fileURLWithPath:path];
}

static void fill(NSManagedObjectContext *moc)
{
    Department *d = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
    d.title = @"Research";
    d.budget = 1250.5;
    Person *ann = new_person(moc, @"Ann", 41);
    ann.score = @2.25;
    ann.born = [NSDate dateWithTimeIntervalSinceReferenceDate:123456.5];
    ann.active = NO;
    ann.nickname = @"not kept";
    ann.tags = @[ @"x", @"y" ];
    ann.uuid = [[NSUUID alloc] initWithUUIDString:@"0E3A8F2C-4B5D-4E6F-8A9B-0C1D2E3F4A5B"];
    ann.home = [NSURL URLWithString:@"file:///Users/ann/"];
    ann.photo = [NSData dataWithBytes:"\x00\x01\x02\xff" length:4];
    ann.department = d;
    Manager *bob = [NSEntityDescription insertNewObjectForEntityForName:@"Manager" inManagedObjectContext:moc];
    bob.name = @"Bob";
    bob.age = 50;
    bob.level = 3;
    bob.department = d;
    for (NSString *plate in @[ @"P-1", @"P-2" ]) {
        Car *c = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        c.plate = plate;
        c.owner = ann;
    }
    for (NSString *t in @[ @"c", @"a", @"b" ]) {
        Note *n = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:moc];
        n.text = t;
        [ann addNotesObject:n];
    }
}

static void check(NSManagedObjectContext *moc)
{
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSError *error = nil;
    NSArray *people = [moc executeFetchRequest:f error:&error];
    Person *ann = people[0];
    printf("  %lu people, the first a fault until used: %d\n", (unsigned long)people.count, ann.isFault);
    printf("  people: %s (%s)\n", str(names(people)), str(error));
    printf("  ann: age %d score %s active %d born %.1f nickname %s\n", ann.age, str(ann.score), ann.active,
           ann.born.timeIntervalSinceReferenceDate, str(ann.nickname));
    printf("  ann: tags %s uuid %s home %s photo %s\n", str([ann.tags componentsJoinedByString:@"+"]),
           str(ann.uuid.UUIDString), str(ann.home), str(ann.photo));
    printf("  ann: department %s (budget %.1f), cars %s, notes %s\n", str(ann.department.title), ann.department.budget,
           str(sorted_names(ann.cars)), str(names(ann.notes)));
    Manager *bob = people[1];
    printf("  bob: class %s, entity %s, level %d, department %s\n", object_getClassName(bob), str(bob.entity.name),
           bob.level, str(bob.department.title));
    printf("  research employees: %s\n", str(sorted_names(ann.department.employees)));
    NSManagedObjectID *oid = ann.objectID;
    NSManagedObjectID *back = [moc.persistentStoreCoordinator managedObjectIDForURIRepresentation:oid.URIRepresentation];
    printf("  uri round trip: %d, permanent %d\n", [back isEqual:oid], !oid.isTemporaryID);
}

static void round_trip(NSString *type, NSURL *url)
{
    printf("%s store:\n", type.UTF8String);
    NSManagedObjectModel *model = people_model();
    NSManagedObjectContext *moc = people_context(model, type, url, nil);
    fill(moc);
    NSError *error = nil;
    printf("  saved: %d %s\n", [moc save:&error], str(error));
    NSPersistentStore *store = moc.persistentStoreCoordinator.persistentStores.firstObject;
    printf("  store type %s, url %s\n", str(store.type), str(store.URL.lastPathComponent));
    NSString *identifier = store.identifier;
    NSMutableDictionary *meta = [store.metadata mutableCopy];
    meta[@"Colour"] = @"teal";
    [moc.persistentStoreCoordinator setMetadata:meta forPersistentStore:store];
    /* a change after the first save, and a delete */
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Car"];
    f.predicate = [NSPredicate predicateWithFormat:@"plate == 'P-2'"];
    Car *p2 = [[moc executeFetchRequest:f error:&error] firstObject];
    p2.plate = @"P-3";
    f.predicate = [NSPredicate predicateWithFormat:@"plate == 'P-1'"];
    [moc deleteObject:[[moc executeFetchRequest:f error:&error] firstObject]];
    printf("  saved again: %d\n", [moc save:&error]);
    moc = nil;

    NSDictionary *m = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:type URL:url options:nil error:&error];
    printf("  metadata: type %s, same uuid %d, colour %s, hashes %lu, compatible %d\n", str(m[NSStoreTypeKey]),
           [m[NSStoreUUIDKey] isEqual:identifier], str(m[@"Colour"]), (unsigned long)[m[NSStoreModelVersionHashesKey] count],
           [model isConfiguration:nil compatibleWithStoreMetadata:m]);
    NSManagedObjectContext *again = people_context(people_model(), type, url, nil);
    check(again);
}

int main(void)
{
    @autoreleasepool {
        round_trip(NSSQLiteStoreType, file(@"people.sqlite"));
        round_trip(NSBinaryStoreType, file(@"people.bin"));

        printf("in-memory store:\n");
        NSManagedObjectContext *mem = people_context(people_model(), NSInMemoryStoreType, nil, nil);
        fill(mem);
        NSError *error = nil;
        printf("  saved: %d\n", [mem save:&error]);
        [mem reset];
        check(mem);

        printf("metadata set on a closed file:\n");
        NSURL *url = file(@"people.sqlite");
        NSManagedObjectContext *moc = people_context(people_model(), NSSQLiteStoreType, url, nil);
        new_person(moc, @"Cy", 9);
        [moc save:&error];
        moc = nil;
        NSMutableDictionary *meta =
            [[NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType URL:url options:nil
                                                                      error:&error] mutableCopy];
        meta[@"Note"] = @"written while closed";
        printf("  set: %d\n", [NSPersistentStoreCoordinator setMetadata:meta forPersistentStoreOfType:NSSQLiteStoreType
                                                                    URL:url options:nil error:&error]);
        NSDictionary *read = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:url options:nil
                                                                                      error:&error];
        printf("  read without a type: %s, %s\n", str(read[NSStoreTypeKey]), str(read[@"Note"]));

        printf("a container with a store description:\n");
        NSPersistentContainer *c = [NSPersistentContainer persistentContainerWithName:@"People"
                                                                   managedObjectModel:people_model()];
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
        printf("  default store: %s in Application Support %d\n", str(c.persistentStoreDescriptions[0].URL.lastPathComponent),
               [c.persistentStoreDescriptions[0].URL.path isEqual:[support stringByAppendingPathComponent:@"People.sqlite"]]);
        NSPersistentStoreDescription *d = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:file(@"c.db")];
        d.type = NSSQLiteStoreType;
        c.persistentStoreDescriptions = @[ d ];
        __block int calls = 0;
        [c loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *e) {
            calls++;
            printf("  loaded %s: %s\n", str(desc.URL.lastPathComponent), str(e));
        }];
        new_person(c.viewContext, @"Dee", 30);
        printf("  saved: %d, calls %d, concurrency main %d\n", [c.viewContext save:&error], calls,
               c.viewContext.concurrencyType == NSMainQueueConcurrencyType);
        NSPersistentContainer *c2 = [NSPersistentContainer persistentContainerWithName:@"People"
                                                                    managedObjectModel:people_model()];
        c2.persistentStoreDescriptions = @[ d ];
        [c2 loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *e) {}];
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        printf("  second container finds %lu\n", (unsigned long)[c2.viewContext countForFetchRequest:f error:&error]);
        NSPersistentContainer *c3 = [NSPersistentContainer persistentContainerWithName:@"People"
                                                                    managedObjectModel:people_model()];
        [c3 loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *e) {
            printf("  default location loads: %s, file there %d\n", str(e),
                   [[NSFileManager defaultManager] fileExistsAtPath:desc.URL.path]);
        }];

        printf("not a store:\n");
        NSURL *junk = file(@"junk.sqlite");
        [@"this is not a database, only text that is long enough to read" writeToURL:junk atomically:YES
                                                                            encoding:NSUTF8StringEncoding error:NULL];
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:people_model()];
        id s = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:junk options:nil error:&error];
        printf("  added %d, error %ld\n", s != nil, (long)error.code);
        s = [psc addPersistentStoreWithType:@"Imaginary" configuration:nil URL:junk options:nil error:&error];
        printf("  unknown type: added %d, error %ld\n", s != nil, (long)error.code);
        NSManagedObjectContext *none = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        none.persistentStoreCoordinator = psc;
        new_person(none, @"Eve", 1);
        printf("  save with no store: %d, error %ld\n", [none save:&error], (long)error.code);
    }
    return 0;
}
