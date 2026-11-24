/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Data with expressions and decimals (freemac 1.NEXT, Ferry 0.NEXT):
 * decimal attributes kept exactly in the SQLite, binary and in-memory
 * stores, older SQLite and binary stores that kept them as doubles,
 * NSExpressionDescription in propertiesToFetch with aggregates,
 * propertiesToGroupBy, havingPredicate, sorting and limits of the groups,
 * expressions for each object, and MATCHES in fetches. */
#import <CoreData/CoreData.h>
#include <stdio.h>

/* For making an SQLite store the way an older Ferry did. */
typedef struct sqlite3 sqlite3;
extern int sqlite3_open(const char *, sqlite3 **);
extern int sqlite3_exec(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
extern int sqlite3_close(sqlite3 *);

static const char *str(id v) { return v ? [[v description] UTF8String] : "nil"; }

static int print_row(void *unused, int n, char **values, char **names)
{
    for (int i = 0; i < n; i++)
        printf(" %s", values[i] ? values[i] : "NULL");
    return 0;
}

static NSAttributeDescription *attribute(NSString *name, NSAttributeType type)
{
    NSAttributeDescription *a = [NSAttributeDescription new];
    a.name = name;
    a.attributeType = type;
    return a;
}

static NSManagedObjectModel *model(void)
{
    NSEntityDescription *item = [NSEntityDescription new];
    item.name = @"Item";
    item.managedObjectClassName = @"NSManagedObject";
    item.properties = @[ attribute(@"name", NSStringAttributeType), attribute(@"price", NSDecimalAttributeType),
                         attribute(@"qty", NSInteger32AttributeType), attribute(@"category", NSStringAttributeType) ];
    NSManagedObjectModel *m = [NSManagedObjectModel new];
    m.entities = @[ item ];
    return m;
}

static NSManagedObjectContext *open_store(NSManagedObjectModel *m, NSString *type, NSURL *url)
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:m];
    NSError *error = nil;
    if (![psc addPersistentStoreWithType:type configuration:nil URL:url options:nil error:&error]) {
        printf("can't open the %s store: %s\n", type.UTF8String, str(error));
        return nil;
    }
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    moc.persistentStoreCoordinator = psc;
    return moc;
}

static void fill(NSManagedObjectContext *moc)
{
    NSArray *rows = @[ @[ @"Apple", @"0.1", @3, @"fruit" ], @[ @"Bread", @"2.35", @1, @"bakery" ],
                       @[ @"Cherry", @"0.2", @10, @"fruit" ], @[ @"Donut", @"1.05", @6, @"bakery" ],
                       @[ @"Eggs", @"3.333333333333333333333333333333", @12, @"dairy" ],
                       @[ @"Fig", @"12345678901234567890.12345", @2, @"fruit" ], @[ @"Gum", [NSNull null], @5, [NSNull null] ] ];
    for (NSArray *r in rows) {
        NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:moc];
        [o setValue:r[0] forKey:@"name"];
        if (r[1] != [NSNull null])
            [o setValue:[NSDecimalNumber decimalNumberWithString:r[1]] forKey:@"price"];
        [o setValue:r[2] forKey:@"qty"];
        if (r[3] != [NSNull null])
            [o setValue:r[3] forKey:@"category"];
    }
    NSError *error = nil;
    if (![moc save:&error])
        printf("save failed: %s\n", str(error));
}

static NSArray *sorted_by_name(void) { return @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]; }

static void show_prices(NSManagedObjectContext *moc)
{
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
    f.sortDescriptors = sorted_by_name();
    for (NSManagedObject *o in [moc executeFetchRequest:f error:NULL]) {
        id price = [o valueForKey:@"price"];
        printf("  %s %s%s\n", str([o valueForKey:@"name"]), str(price),
               price && ![price isKindOfClass:[NSDecimalNumber class]] ? " (not a decimal number)" : "");
    }
    NSDecimalNumber *sum = [[moc executeFetchRequest:f error:NULL] valueForKeyPath:@"@sum.price"];
    printf("  sum %s\n", str(sum));
}

static NSExpressionDescription *expression(NSString *name, NSString *format, NSAttributeType type)
{
    NSExpressionDescription *d = [NSExpressionDescription new];
    d.name = name;
    d.expression = [NSExpression expressionWithFormat:format];
    d.expressionResultType = type;
    return d;
}

static void dictionaries(const char *label, NSManagedObjectContext *moc, NSFetchRequest *f)
{
    NSError *error = nil;
    NSArray *r = nil;
    @try {
        r = [moc executeFetchRequest:f error:&error];
    } @catch (NSException *x) {
        printf(" %s: %s\n", label, x.name.UTF8String);
        return;
    }
    printf(" %s:\n", label);
    for (NSDictionary *d in r) {
        printf("   ");
        for (NSString *k in [[d allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            id v = d[k];
            const char *kind = [v isKindOfClass:[NSDecimalNumber class]] ? "D"
                               : [v isKindOfClass:[NSManagedObjectID class]] ? "ID"
                               : [v isKindOfClass:[NSNumber class]] ? [v objCType]
                                                                    : "";
            printf(" %s=%s%s%s", k.UTF8String, [v isKindOfClass:[NSManagedObjectID class]] ? "(object ID)" : str(v),
                   *kind ? "/" : "", kind);
        }
        printf("\n");
    }
}

static NSFetchRequest *request(void)
{
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
    f.resultType = NSDictionaryResultType;
    return f;
}

static void expressions(NSManagedObjectContext *moc)
{
    NSFetchRequest *f = request();
    f.propertiesToFetch = @[ expression(@"total", @"sum:(price)", NSDecimalAttributeType),
                             expression(@"items", @"count:(name)", NSInteger64AttributeType),
                             expression(@"priced", @"count:(price)", NSInteger64AttributeType),
                             expression(@"cheapest", @"min:(price)", NSDecimalAttributeType),
                             expression(@"dearest", @"max:(price)", NSDecimalAttributeType),
                             expression(@"meanQty", @"average:(qty)", NSDoubleAttributeType),
                             expression(@"most", @"max:(qty) * 2", NSInteger32AttributeType) ];
    dictionaries("aggregates over everything", moc, f);

    f.predicate = [NSPredicate predicateWithFormat:@"category == 'fruit'"];
    dictionaries("aggregates over fruit", moc, f);

    f.predicate = [NSPredicate predicateWithFormat:@"qty > 100"];
    dictionaries("aggregates over nothing", moc, f);

    f = request();
    f.propertiesToFetch = @[ @"category", expression(@"total", @"sum:(price)", NSDecimalAttributeType),
                             expression(@"count", @"count:(name)", NSInteger64AttributeType),
                             expression(@"qty", @"sum:(qty)", NSInteger64AttributeType) ];
    f.propertiesToGroupBy = @[ @"category" ];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"category" ascending:YES] ];
    dictionaries("grouped by category", moc, f);

    f.havingPredicate = [NSPredicate predicateWithFormat:@"count > 1"];
    dictionaries("having more than one", moc, f);

    f.havingPredicate = [NSPredicate predicateWithFormat:@"$total < 5"];
    dictionaries("having a total under 5", moc, f);

    f.havingPredicate = nil;
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"qty" ascending:NO] ];
    f.fetchLimit = 2;
    dictionaries("the two largest", moc, f);

    f.fetchOffset = 1;
    dictionaries("after the largest", moc, f);

    f = request();
    f.propertiesToFetch = @[ @"name", expression(@"total", @"sum:(price)", NSDecimalAttributeType) ];
    dictionaries("a property outside the grouping", moc, f);

    f = request();
    f.propertiesToFetch = @[ @"name", expression(@"twice", @"qty * 2", NSInteger32AttributeType),
                             expression(@"loud", @"uppercase:(name)", NSStringAttributeType),
                             expression(@"me", @"SELF", NSObjectIDAttributeType) ];
    f.predicate = [NSPredicate predicateWithFormat:@"qty >= 6"];
    f.sortDescriptors = sorted_by_name();
    dictionaries("an expression for each object", moc, f);

    f = request();
    f.propertiesToFetch = @[ @"category" ];
    f.propertiesToGroupBy = @[ @"category" ];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"category" ascending:NO] ];
    dictionaries("grouping alone", moc, f);
}

static void matches(NSManagedObjectContext *moc)
{
    NSString *formats[] = { @"name MATCHES '[A-C].*'", @"name MATCHES 'a.*'", @"name MATCHES[c] 'a.*|.*g'",
                            @"category MATCHES 'f.*' AND qty > 2", @"NOT name MATCHES '.{3}'", @"name MATCHES 'C.*y'" };
    for (unsigned i = 0; i < sizeof formats / sizeof *formats; i++) {
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        f.predicate = [NSPredicate predicateWithFormat:formats[i]];
        f.sortDescriptors = sorted_by_name();
        NSArray *r = [[moc executeFetchRequest:f error:NULL] valueForKey:@"name"];
        printf("  %-40s %s (%lu)\n", f.predicate.predicateFormat.UTF8String, [[r componentsJoinedByString:@" "] UTF8String],
               (unsigned long)[moc countForFetchRequest:f error:NULL]);
    }
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
    f.predicate = [NSPredicate predicateWithFormat:@"price > 1 AND price < 3"];
    f.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"price" ascending:NO] ];
    printf("  decimals compared and sorted: %s\n",
           [[[[moc executeFetchRequest:f error:NULL] valueForKey:@"name"] componentsJoinedByString:@" "] UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"coredata_aggregates"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSManagedObjectModel *m = model();

        for (NSString *type in @[ NSSQLiteStoreType, NSBinaryStoreType, NSInMemoryStoreType ]) {
            printf("%s store:\n", type.UTF8String);
            NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[@"items." stringByAppendingString:type]]];
            NSManagedObjectContext *moc = open_store(m, type, url);
            fill(moc);
            if (![type isEqual:NSInMemoryStoreType])
                moc = open_store(m, type, url);   /* read back from the file */
            show_prices(moc);
            expressions(moc);
            printf(" MATCHES:\n");
            matches(moc);
        }

        /* An SQLite store that kept its decimal numbers as doubles, as Ferry 0.35.0 did. */
        printf("an older SQLite store:\n");
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"old.sqlite"]];
        NSManagedObjectContext *moc = open_store(m, NSSQLiteStoreType, url);
        fill(moc);
        moc = nil;
        sqlite3 *db = NULL;
        sqlite3_open(url.path.fileSystemRepresentation, &db);
        char *message = NULL;
        int rc = sqlite3_exec(db,
                              "ALTER TABLE ZITEM RENAME COLUMN ZPRICE TO ZTEXT;"
                              "ALTER TABLE ZITEM ADD COLUMN ZPRICE REAL;"
                              "UPDATE ZITEM SET ZPRICE = CAST(ZTEXT AS REAL);"
                              "ALTER TABLE ZITEM DROP COLUMN ZTEXT;",
                              NULL, NULL, &message);
        printf("  made older: %d %s\n", rc, message ? message : "");
        sqlite3_close(db);
        moc = open_store(m, NSSQLiteStoreType, url);
        show_prices(moc);
        NSManagedObject *bread = [moc executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Item"] error:NULL][1];
        [bread setValue:[NSDecimalNumber decimalNumberWithString:@"0.30000000000000000001"] forKey:@"price"];
        [moc save:NULL];
        moc = open_store(m, NSSQLiteStoreType, url);
        NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Item"];
        f.predicate = [NSPredicate predicateWithFormat:@"name == %@", [bread valueForKey:@"name"]];
        printf("  written after: %s\n", str([[moc executeFetchRequest:f error:NULL][0] valueForKey:@"price"]));
        moc = nil;
        sqlite3_open(url.path.fileSystemRepresentation, &db);
        printf("  the column now:");
        sqlite3_exec(db, "SELECT type FROM pragma_table_info('ZITEM') WHERE name = 'ZPRICE'", print_row, NULL, NULL);
        printf("\n");
        sqlite3_close(db);

        /* A binary store that kept them as doubles. */
        printf("an older binary store:\n");
        url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"old.binary"]];
        moc = open_store(m, NSBinaryStoreType, url);
        fill(moc);
        moc = nil;
        NSMutableDictionary *archive = [[NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfURL:url]] mutableCopy];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *row in archive[@"rows"]) {
            NSMutableDictionary *r = [row mutableCopy], *d = [row[@"d"] mutableCopy];
            if (d[@"price"])
                d[@"price"] = @([d[@"price"] doubleValue]);
            r[@"d"] = d;
            [rows addObject:r];
        }
        archive[@"rows"] = rows;
        [[NSKeyedArchiver archivedDataWithRootObject:archive] writeToURL:url atomically:YES];
        moc = open_store(m, NSBinaryStoreType, url);
        show_prices(moc);
    }
    return 0;
}
