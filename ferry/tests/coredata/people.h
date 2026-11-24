/* SPDX-License-Identifier: GPL-3.0-or-later
 * The model Core Data's tests share (freemac 1.209, Ferry 0.35.0), built
 * in code: people in departments, with cars and notes, and managers as a
 * kind of person.
 *
 *   Department  title (string, required), budget (double)
 *               employees -> Person, to-many, inverse department, deny
 *   Person      name (string, required, 1 to 20 characters), age (int16,
 *               0 to 150, default 0), score (double), born (date), active
 *               (Boolean, default YES), nickname (string, transient),
 *               tags (transformable), uuid (UUID), home (URI), photo (data)
 *               department -> Department, to-one, inverse employees, nullify
 *               cars -> Car, to-many, inverse owner, cascade
 *               notes -> Note, ordered to-many, inverse person, cascade
 *   Manager     (a Person) level (int32, default 1)
 *   Car         plate (string), owner -> Person, inverse cars, nullify
 *   Note        text (string), person -> Person, inverse notes, no action */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }

@class Department, Car, Note;

@interface Person : NSManagedObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int16_t age;
@property (nonatomic, strong) NSNumber *score;
@property (nonatomic, strong) NSDate *born;
@property (nonatomic) BOOL active;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, strong) NSArray *tags;
@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, strong) NSURL *home;
@property (nonatomic, strong) NSData *photo;
@property (nonatomic, strong) Department *department;
@property (nonatomic, strong) NSSet *cars;
@property (nonatomic, strong) NSOrderedSet *notes;
@end

@interface Person (CoreDataGeneratedAccessors)
- (void)addCarsObject:(Car *)value;
- (void)removeCarsObject:(Car *)value;
- (void)addCars:(NSSet *)values;
- (void)insertObject:(Note *)value inNotesAtIndex:(NSUInteger)idx;
- (void)removeObjectFromNotesAtIndex:(NSUInteger)idx;
- (void)addNotesObject:(Note *)value;
@end

@interface Manager : Person
@property (nonatomic) int32_t level;
@end

@interface Department : NSManagedObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic) double budget;
@property (nonatomic, strong) NSSet *employees;
@end

@interface Department (CoreDataGeneratedAccessors)
- (void)addEmployeesObject:(Person *)value;
- (void)removeEmployeesObject:(Person *)value;
@end

@interface Car : NSManagedObject
@property (nonatomic, copy) NSString *plate;
@property (nonatomic, strong) Person *owner;
@end

@interface Note : NSManagedObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) Person *person;
@end

@implementation Person
@dynamic name, age, score, born, active, nickname, tags, uuid, home, photo, department, cars, notes;
@end
@implementation Manager
@dynamic level;
@end
@implementation Department
@dynamic title, budget, employees;
@end
@implementation Car
@dynamic plate, owner;
@end
@implementation Note
@dynamic text, person;
@end

static NSAttributeDescription *attribute(NSString *name, NSAttributeType type, BOOL optional, id def)
{
    NSAttributeDescription *a = [[NSAttributeDescription alloc] init];
    [a setName:name];
    [a setAttributeType:type];
    [a setOptional:optional];
    [a setDefaultValue:def];
    return a;
}

static NSRelationshipDescription *relationship(NSString *name, NSEntityDescription *to, BOOL toMany, NSDeleteRule rule)
{
    NSRelationshipDescription *r = [[NSRelationshipDescription alloc] init];
    [r setName:name];
    [r setDestinationEntity:to];
    [r setMinCount:0];
    [r setMaxCount:toMany ? 0 : 1];
    [r setDeleteRule:rule];
    [r setOptional:YES];
    return r;
}

static void inverse(NSRelationshipDescription *a, NSRelationshipDescription *b)
{
    [a setInverseRelationship:b];
    [b setInverseRelationship:a];
}

/* The model; extra (may be NULL) adds to the Person entity's attributes. */
static NSManagedObjectModel *people_model_with(NSArray *extra)
{
    NSEntityDescription *dept = [[NSEntityDescription alloc] init], *person = [[NSEntityDescription alloc] init];
    NSEntityDescription *manager = [[NSEntityDescription alloc] init], *car = [[NSEntityDescription alloc] init];
    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [dept setName:@"Department"];
    [dept setManagedObjectClassName:@"Department"];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"Person"];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"Manager"];
    [car setName:@"Car"];
    [car setManagedObjectClassName:@"Car"];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"Note"];

    NSRelationshipDescription *employees = relationship(@"employees", person, YES, NSDenyDeleteRule);
    NSRelationshipDescription *department = relationship(@"department", dept, NO, NSNullifyDeleteRule);
    inverse(employees, department);
    NSRelationshipDescription *cars = relationship(@"cars", car, YES, NSCascadeDeleteRule);
    NSRelationshipDescription *owner = relationship(@"owner", person, NO, NSNullifyDeleteRule);
    inverse(cars, owner);
    NSRelationshipDescription *notes = relationship(@"notes", note, YES, NSCascadeDeleteRule);
    [notes setOrdered:YES];
    NSRelationshipDescription *noteOf = relationship(@"person", person, NO, NSNoActionDeleteRule);
    inverse(notes, noteOf);

    [dept setProperties:@[ attribute(@"title", NSStringAttributeType, NO, nil),
                           attribute(@"budget", NSDoubleAttributeType, YES, @0.0), employees ]];

    NSAttributeDescription *name = attribute(@"name", NSStringAttributeType, NO, nil);
    [name setValidationPredicates:@[ [NSPredicate predicateWithFormat:@"length >= 1"],
                                     [NSPredicate predicateWithFormat:@"length <= 20"] ]
           withValidationWarnings:@[ @"NSValidationStringTooShortError", @"NSValidationStringTooLongError" ]];
    NSAttributeDescription *age = attribute(@"age", NSInteger16AttributeType, YES, @0);
    [age setValidationPredicates:@[ [NSPredicate predicateWithFormat:@"SELF >= 0"],
                                    [NSPredicate predicateWithFormat:@"SELF <= 150"] ]
          withValidationWarnings:@[ @"NSValidationNumberTooSmallError", @"NSValidationNumberTooLargeError" ]];
    NSAttributeDescription *nickname = attribute(@"nickname", NSStringAttributeType, YES, nil);
    [nickname setTransient:YES];
    NSAttributeDescription *tags = attribute(@"tags", NSTransformableAttributeType, YES, nil);
    [tags setValueTransformerName:NSKeyedUnarchiveFromDataTransformerName];
    NSMutableArray *props = [NSMutableArray arrayWithObjects:name, age,
                                            attribute(@"score", NSDoubleAttributeType, YES, nil),
                                            attribute(@"born", NSDateAttributeType, YES, nil),
                                            attribute(@"active", NSBooleanAttributeType, YES, @YES), nickname, tags,
                                            attribute(@"uuid", NSUUIDAttributeType, YES, nil),
                                            attribute(@"home", NSURIAttributeType, YES, nil),
                                            attribute(@"photo", NSBinaryDataAttributeType, YES, nil), department, cars,
                                            notes, nil];
    if (extra)
        [props addObjectsFromArray:extra];
    [person setProperties:props];
    [manager setProperties:@[ attribute(@"level", NSInteger32AttributeType, YES, @1) ]];
    [person setSubentities:@[ manager ]];
    [car setProperties:@[ attribute(@"plate", NSStringAttributeType, YES, nil), owner ]];
    [note setProperties:@[ attribute(@"text", NSStringAttributeType, YES, nil), noteOf ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ dept, person, manager, car, note ]];
    return model;
}

static NSManagedObjectModel *people_model(void) { return people_model_with(nil); }

/* A main-queue context on a new coordinator with one store of the type (at url, if given). */
static NSManagedObjectContext *people_context(NSManagedObjectModel *model, NSString *type, NSURL *url,
                                              NSDictionary *options)
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    if (![psc addPersistentStoreWithType:type configuration:nil URL:url options:options error:&error]) {
        printf("store not added: %ld %s\n", (long)[error code], str([error localizedDescription]));
        return nil;
    }
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [moc setPersistentStoreCoordinator:psc];
    return moc;
}

static Person *new_person(NSManagedObjectContext *moc, NSString *name, int age)
{
    Person *p = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:moc];
    p.name = name;
    p.age = (int16_t)age;
    return p;
}

static NSString *names(id collection)
{
    NSMutableArray *a = [NSMutableArray array];
    for (id o in collection)
        [a addObject:[o valueForKey:[[[o entity] attributesByName] objectForKey:@"name"] ? @"name"
                                    : [[[o entity] attributesByName] objectForKey:@"title"] ? @"title"
                                    : [[[o entity] attributesByName] objectForKey:@"plate"] ? @"plate"
                                                                                           : @"text"] ?: @"nil"];
    return [a componentsJoinedByString:@","];
}

static NSString *sorted_names(id collection)
{
    NSArray *parts = [names(collection) componentsSeparatedByString:@","];
    return [[parts sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
}

static void spin(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
