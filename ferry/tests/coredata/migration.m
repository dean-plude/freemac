/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's lightweight migration (freemac 1.209, Ferry 0.35.0), for the
 * SQLite and binary stores: a store made with one model and opened with a
 * model that adds optional attributes (one with a default value, which the
 * old rows are given) and a new entity, and removes an attribute; refused
 * without the migration options (NSPersistentStoreIncompatibleVersionHashError),
 * refused for a new required attribute with no default value and for an
 * attribute whose type changed; and the store's metadata afterwards. */
#import "people.h"

static NSAttributeDescription *attr(NSString *name, NSAttributeType type, BOOL optional, id def)
{
    return attribute(name, type, optional, def);
}

/* The people model with Person changed: added attributes, and without "photo" when drop is set. */
static NSManagedObjectModel *changed_model(NSArray *added, BOOL drop, BOOL withBadge)
{
    NSManagedObjectModel *m = people_model_with(added);
    NSEntityDescription *person = m.entitiesByName[@"Person"];
    if (drop) {
        NSMutableArray *props = [person.properties mutableCopy];
        [props removeObject:person.propertiesByName[@"photo"]];
        person.properties = props;
    }
    if (withBadge) {
        NSEntityDescription *badge = [[NSEntityDescription alloc] init];
        badge.name = @"Badge";
        badge.properties = @[ attr(@"code", NSStringAttributeType, YES, nil) ];
        m.entities = [m.entities arrayByAddingObject:badge];
    }
    return m;
}

static NSDictionary *migrate(void)
{
    return @{ NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };
}

static void attempt(const char *what, NSManagedObjectModel *model, NSString *type, NSURL *url, NSDictionary *options)
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    id s = [psc addPersistentStoreWithType:type configuration:nil URL:url options:options error:&error];
    printf("  %-40s added %d, error %ld\n", what, s != nil, (long)error.code);
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_migration"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *type in @[ NSSQLiteStoreType, NSBinaryStoreType ]) {
            printf("%s store:\n", type.UTF8String);
            NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[@"m." stringByAppendingString:type]]];
            NSManagedObjectContext *moc = people_context(people_model(), type, url, nil);
            Person *ann = new_person(moc, @"Ann", 30);
            ann.photo = [@"old" dataUsingEncoding:NSUTF8StringEncoding];
            new_person(moc, @"Bob", 40);
            NSError *error = nil;
            [moc save:&error];
            moc = nil;

            NSArray *added = @[ attr(@"email", NSStringAttributeType, YES, nil),
                                attr(@"rank", NSInteger32AttributeType, YES, @7) ];
            NSManagedObjectModel *v2 = changed_model(added, YES, YES);
            NSDictionary *meta = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:type URL:url options:nil
                                                                                         error:&error];
            printf("  v2 compatible with the store: %d\n", [v2 isConfiguration:nil compatibleWithStoreMetadata:meta]);
            attempt("v2 without the migration options:", v2, type, url, nil);
            NSManagedObjectModel *required = changed_model(@[ attr(@"code", NSStringAttributeType, NO, nil) ], NO, NO);
            attempt("a required attribute with no default:", required, type, url, migrate());
            NSManagedObjectModel *retyped = people_model();
            [(NSAttributeDescription *)retyped.entitiesByName[@"Person"].propertiesByName[@"score"]
                setAttributeType:NSStringAttributeType];
            attempt("an attribute whose type changed:", retyped, type, url, migrate());

            moc = people_context(v2, type, url, migrate());
            NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
            f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
            for (NSManagedObject *p in [moc executeFetchRequest:f error:&error])
                printf("  migrated %s: age %s, email %s, rank %s, photo key gone %d\n", str([p valueForKey:@"name"]),
                       str([p valueForKey:@"age"]), str([p valueForKey:@"email"]), str([p valueForKey:@"rank"]),
                       p.entity.propertiesByName[@"photo"] == nil);
            NSManagedObject *carol = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:moc];
            [carol setValue:@"Carol" forKey:@"name"];
            [carol setValue:@"carol@example.com" forKey:@"email"];
            NSManagedObject *badge = [NSEntityDescription insertNewObjectForEntityForName:@"Badge" inManagedObjectContext:moc];
            [badge setValue:@"B-1" forKey:@"code"];
            printf("  saved with the new model: %d %s\n", [moc save:&error], str(error));
            NSPersistentStore *store = moc.persistentStoreCoordinator.persistentStores[0];
            printf("  store metadata now matches v2: %d, entities %lu\n",
                   [v2 isConfiguration:nil compatibleWithStoreMetadata:store.metadata],
                   (unsigned long)[store.metadata[NSStoreModelVersionHashesKey] count]);
            moc = nil;
            moc = people_context(changed_model(added, YES, YES), type, url, nil);
            f.predicate = [NSPredicate predicateWithFormat:@"email != nil"];
            printf("  reopened without options: %s with email\n", str(names([moc executeFetchRequest:f error:&error])));
            f = [NSFetchRequest fetchRequestWithEntityName:@"Badge"];
            printf("  badges: %lu\n", (unsigned long)[moc countForFetchRequest:f error:&error]);
            attempt("the old model on the new store:", people_model(), type, url, nil);
        }
    }
    return 0;
}
