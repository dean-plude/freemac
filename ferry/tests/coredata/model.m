/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data's model and objects (freemac 1.209, Ferry 0.35.0), in an
 * in-memory store: a model built in code (attribute types, defaults,
 * optional and transient attributes, a transformable one, entity
 * inheritance), @dynamic accessors for objects and scalars, KVC, KVO and
 * the to-many mutable proxies, primitive values, inverses kept as
 * relationships change (to-one, to-many and ordered), the delete rules
 * (nullify, cascade, deny, no action), changed values and the object's
 * flags, and validation with the documented error codes. */
#import "people.h"

@interface Watcher : NSObject
@property (nonatomic, strong) NSMutableArray *seen;
@end
@implementation Watcher
- (instancetype)init
{
    if ((self = [super init]))
        _seen = [NSMutableArray array];
    return self;
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSNumber *kind = change[NSKeyValueChangeKindKey];
    [_seen addObject:[NSString stringWithFormat:@"%@:%@", path, kind]];
}
@end

static void show_error(const char *what, NSError *e)
{
    printf("%s: %ld", what, (long)[e code]);
    if ([e code] == NSValidationMultipleErrorsError) {
        NSMutableArray *codes = [NSMutableArray array];
        for (NSError *d in e.userInfo[NSDetailedErrorsKey])
            [codes addObject:[NSString stringWithFormat:@"%ld/%@", (long)[d code], d.userInfo[NSValidationKeyErrorKey]]];
        printf(" [%s]", [[codes componentsJoinedByString:@" "] UTF8String]);
    } else if (e.userInfo[NSValidationKeyErrorKey])
        printf(" key %s", str(e.userInfo[NSValidationKeyErrorKey]));
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSManagedObjectModel *model = people_model();
        NSEntityDescription *person = model.entitiesByName[@"Person"];
        NSEntityDescription *manager = model.entitiesByName[@"Manager"];
        printf("entities: %s\n", [[[model.entitiesByName.allKeys sortedArrayUsingSelector:@selector(compare:)]
                                      componentsJoinedByString:@","] UTF8String]);
        printf("manager super: %s, kind of person: %d, person kind of manager: %d\n", str(manager.superentity.name),
               [manager isKindOfEntity:person], [person isKindOfEntity:manager]);
        printf("manager attributes: %lu, has name: %d, level: %s\n", (unsigned long)manager.attributesByName.count,
               manager.attributesByName[@"name"] != nil, str(manager.attributesByName[@"level"].attributeValueClassName));
        NSRelationshipDescription *cars = person.relationshipsByName[@"cars"];
        printf("cars: to-many %d, inverse %s, rule %lu; notes ordered %d\n", cars.isToMany,
               str(cars.inverseRelationship.name), (unsigned long)cars.deleteRule,
               person.relationshipsByName[@"notes"].isOrdered);
        printf("version hashes: %lu entities, person hash %lu bytes\n", (unsigned long)model.entityVersionHashesByName.count,
               (unsigned long)[model.entityVersionHashesByName[@"Person"] length]);

        NSManagedObjectContext *moc = people_context(model, NSInMemoryStoreType, nil, nil);
        Person *ann = new_person(moc, @"Ann", 41);
        printf("ann: class %s, entity %s, inserted %d, temporary %d, active %d (default)\n",
               object_getClassName(ann), str(ann.entity.name), ann.isInserted, ann.objectID.isTemporaryID, ann.active);
        ann.score = @3.5;
        ann.born = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
        ann.nickname = @"Annie";
        ann.tags = @[ @"red", @"blue" ];
        ann.uuid = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
        ann.home = [NSURL URLWithString:@"https://example.com/ann"];
        ann.photo = [@"jpeg" dataUsingEncoding:NSUTF8StringEncoding];
        printf("ann: %s %d %s %s %s %s %s\n", str(ann.name), ann.age, str(ann.score), str(ann.nickname),
               str([ann.tags componentsJoinedByString:@"+"]), str(ann.uuid.UUIDString), str(ann.home));
        printf("kvc: age %s, active %s, name %s\n", str([ann valueForKey:@"age"]), str([ann valueForKey:@"active"]),
               str([ann valueForKey:@"name"]));
        [ann setValue:@42 forKey:@"age"];
        printf("after setValue: age %d, primitive %s\n", ann.age, str([ann primitiveValueForKey:@"age"]));

        Manager *bob = [NSEntityDescription insertNewObjectForEntityForName:@"Manager" inManagedObjectContext:moc];
        bob.name = @"Bob";
        printf("bob: class %s, level %d, age %d, kind of Person %d\n", object_getClassName(bob), bob.level, bob.age,
               [bob isKindOfClass:[Person class]]);

        /* KVO on modeled properties, and through relationships */
        Watcher *w = [[Watcher alloc] init];
        [ann addObserver:w forKeyPath:@"name" options:0 context:NULL];
        [ann addObserver:w forKeyPath:@"cars" options:0 context:NULL];
        [ann addObserver:w forKeyPath:@"department.title" options:0 context:NULL];
        ann.name = @"Anne";

        /* inverses: to-one and to-many */
        Department *eng = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:moc];
        eng.title = @"Engineering";
        ann.department = eng;
        printf("eng employees after ann.department = eng: %s\n", str(sorted_names(eng.employees)));
        [eng addEmployeesObject:bob];
        printf("bob.department after addEmployeesObject: %s\n", str(bob.department.title));
        eng.title = @"Eng";
        Car *c1 = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        c1.plate = @"AB-1";
        Car *c2 = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        c2.plate = @"CD-2";
        [ann addCarsObject:c1];
        [[ann mutableSetValueForKey:@"cars"] addObject:c2];
        printf("ann cars: %s, c2 owner %s\n", str(sorted_names(ann.cars)), str(c2.owner.name));
        c2.owner = bob;
        printf("after c2.owner = bob: ann %s, bob %s\n", str(sorted_names(ann.cars)), str(sorted_names(bob.cars)));
        printf("kvo seen: %s\n", [[w.seen componentsJoinedByString:@" "] UTF8String]);
        [ann removeObserver:w forKeyPath:@"name"];
        [ann removeObserver:w forKeyPath:@"cars"];
        [ann removeObserver:w forKeyPath:@"department.title"];

        /* an ordered to-many */
        for (NSString *t in @[ @"one", @"two", @"three" ]) {
            Note *n = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:moc];
            n.text = t;
            [ann addNotesObject:n];
        }
        Note *zero = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:moc];
        zero.text = @"zero";
        [ann insertObject:zero inNotesAtIndex:0];
        [[ann mutableOrderedSetValueForKey:@"notes"] removeObjectAtIndex:2];
        printf("notes: %s, zero.person %s\n", str(names(ann.notes)), str(zero.person.name));

        /* saving gives permanent IDs and clears the flags */
        NSError *error = nil;
        printf("hasChanges %d, inserted %lu\n", moc.hasChanges, (unsigned long)moc.insertedObjects.count);
        printf("save: %d\n", [moc save:&error]);
        printf("after save: hasChanges %d, temporary %d, uri %s\n", moc.hasChanges, ann.objectID.isTemporaryID,
               [[ann.objectID.URIRepresentation.absoluteString hasPrefix:@"x-coredata://"] ? @"x-coredata" : @"other"
                   UTF8String]);
        ann.age = 43;
        ann.nickname = @"A";
        printf("changed: %s, updated %d, committed age %s\n",
               str([[ann.changedValues.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]),
               ann.isUpdated, str([ann committedValuesForKeys:@[ @"age" ]][@"age"]));
        [moc save:&error];

        /* the delete rules: deny, then nullify and cascade */
        [moc deleteObject:eng];
        printf("save with deny: %d, ", [moc save:&error]);
        show_error("error", error);
        [moc rollback];
        printf("eng after rollback: deleted %d, employees %s\n", eng.isDeleted, str(sorted_names(eng.employees)));
        ann.department = nil;
        bob.department = nil;
        [moc deleteObject:eng];
        printf("save after emptying: %d\n", [moc save:&error]);
        NSManagedObjectID *c1id = c1.objectID;
        [moc deleteObject:ann];
        [moc processPendingChanges];
        printf("ann deleted %d; cascaded: c1 %d, notes %lu deleted\n", ann.isDeleted, c1.isDeleted,
               (unsigned long)[[moc.deletedObjects filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == 'Note'"]] count]);
        printf("save: %d; c1 gone: %d\n", [moc save:&error], [moc existingObjectWithID:c1id error:NULL] == nil);
        Note *memo = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:moc];
        memo.text = @"memo";
        memo.person = bob;
        [moc deleteObject:memo];
        [moc processPendingChanges];
        printf("deleting a note (no action) leaves bob's notes: %s\n", str(names(bob.notes)));
        [moc rollback];
        Car *c3 = [NSEntityDescription insertNewObjectForEntityForName:@"Car" inManagedObjectContext:moc];
        c3.owner = bob;
        [moc deleteObject:c3];
        [moc processPendingChanges];
        printf("deleting a car nullifies: bob cars %s\n", str(sorted_names(bob.cars)));

        /* validation */
        Person *p = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:moc];
        printf("validateForInsert empty: %d, ", [p validateForInsert:&error]);
        show_error("error", error);
        id v = @"";
        printf("name '': %d, ", [p validateValue:&v forKey:@"name" error:&error]);
        show_error("error", error);
        v = @"a name that is far too long to be valid";
        printf("long name: %d, ", [p validateValue:&v forKey:@"name" error:&error]);
        show_error("error", error);
        v = @200;
        printf("age 200: %d, ", [p validateValue:&v forKey:@"age" error:&error]);
        show_error("error", error);
        v = @-1;
        printf("age -1: %d, ", [p validateValue:&v forKey:@"age" error:&error]);
        show_error("error", error);
        v = @30;
        printf("age 30: %d\n", [p validateValue:&v forKey:@"age" error:&error]);
        p.age = 200;
        printf("save invalid: %d, ", [moc save:&error]);
        show_error("error", error);
        p.name = @"Pat";
        p.age = 30;
        printf("save valid: %d\n", [moc save:&error]);
        printf("description: %s\n", [[p description] rangeOfString:@"(entity: Person; id: "].location != NSNotFound
                                         ? "Apple's form" : str([p description]));
    }
    return 0;
}
