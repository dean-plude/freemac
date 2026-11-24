/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Data: the SQLite store (freemac 1.NEXT, Ferry 0.NEXT). Our
 * own code, on the host's sqlite3. The tables are Ferry's own, and a store
 * file written by a Mac's Core Data isn't read (nor one of ours by a Mac's):
 *
 *   Z<ROOT>              one table for each root entity, holding its rows and
 *                        those of every entity below it: Z_PK (the primary key),
 *                        Z_ENT (the entity's name), Z_OPT (the row's version),
 *                        a column Z<NAME> for each attribute, and for each
 *                        to-one relationship Z<NAME> (the destination's
 *                        primary key) and Z_<NAME>ENT (its entity's name).
 *   Z_<ROOT>__<NAME>     one table for each to-many relationship: Z_SRC, Z_DST
 *                        and Z_ORD (the place in an ordered relationship).
 *   Z_PRIMARYKEY         the last primary key given out, for each root entity.
 *   Z_METADATA           the store's metadata, as a property list.
 *
 * Names are the model's in upper case. Dates are kept as seconds since the
 * reference date, UUIDs and URLs as text, Booleans as 0 and 1, and decimal
 * numbers as doubles.
 *
 * A fetch puts in SQL the part of its predicate it can say exactly the
 * same way there (comparisons of numbers, dates and strings, to-one
 * relationships and SELF with object IDs, AND, OR and NOT); the context
 * evaluates the whole predicate again on what comes back. */
#import "CDInternal.h"

/* ---- the parts of sqlite3 we use (the SDK has no sqlite3.h) ------------------------------------ */

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
extern int sqlite3_open_v2(const char *, sqlite3 **, int, const char *);
extern int sqlite3_close(sqlite3 *);
extern int sqlite3_prepare_v2(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
extern int sqlite3_step(sqlite3_stmt *);
extern int sqlite3_finalize(sqlite3_stmt *);
extern int sqlite3_bind_int64(sqlite3_stmt *, int, long long);
extern int sqlite3_bind_double(sqlite3_stmt *, int, double);
extern int sqlite3_bind_text(sqlite3_stmt *, int, const char *, int, void (*)(void *));
extern int sqlite3_bind_blob(sqlite3_stmt *, int, const void *, int, void (*)(void *));
extern int sqlite3_bind_null(sqlite3_stmt *, int);
extern int sqlite3_column_count(sqlite3_stmt *);
extern int sqlite3_column_type(sqlite3_stmt *, int);
extern long long sqlite3_column_int64(sqlite3_stmt *, int);
extern double sqlite3_column_double(sqlite3_stmt *, int);
extern const unsigned char *sqlite3_column_text(sqlite3_stmt *, int);
extern const void *sqlite3_column_blob(sqlite3_stmt *, int);
extern int sqlite3_column_bytes(sqlite3_stmt *, int);
extern const char *sqlite3_errmsg(sqlite3 *);
extern int sqlite3_busy_timeout(sqlite3 *, int);

#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_INTEGER 1
#define SQLITE_FLOAT 2
#define SQLITE_TEXT 3
#define SQLITE_BLOB 4
#define SQLITE_NULL 5
#define SQLITE_OPEN_READONLY 0x1
#define SQLITE_OPEN_READWRITE 0x2
#define SQLITE_OPEN_CREATE 0x4
#define SQLITE_OPEN_FULLMUTEX 0x10000
#define SQLITE_TRANSIENT ((void (*)(void *))-1)

/* ---- names --------------------------------------------------------------------------------- */

static NSString *quoted(NSString *name) { return [NSString stringWithFormat:@"\"%@\"", name]; }
static NSString *table_name(NSEntityDescription *e) { return [@"Z" stringByAppendingString:[[[e cd_root] name] uppercaseString]]; }
static NSString *column_name(NSString *property) { return [@"Z" stringByAppendingString:[property uppercaseString]]; }
static NSString *entity_column_name(NSString *property)
{
    return [NSString stringWithFormat:@"Z_%@ENT", [property uppercaseString]];
}
static NSString *join_table_name(NSEntityDescription *e, NSString *relationship)
{
    return [NSString stringWithFormat:@"Z_%@__%@", [[[e cd_root] name] uppercaseString], [relationship uppercaseString]];
}

static NSString *column_type(NSAttributeType t)
{
    switch (t) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType: return @"INTEGER";
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSDateAttributeType: return @"REAL";
    case NSStringAttributeType:
    case NSUUIDAttributeType:
    case NSURIAttributeType: return @"TEXT";
    default: return @"BLOB";
    }
}

/* ---- values ---------------------------------------------------------------------------------- */

/* An attribute's value as the table keeps it. */
static id raw_value(NSAttributeDescription *a, id value)
{
    value = [a cd_storedValue:value];
    if (!value || value == [NSNull null])
        return [NSNull null];
    switch ([a attributeType]) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType:
        return [value respondsToSelector:@selector(longLongValue)] ? @([value longLongValue]) : [NSNull null];
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
        return [value respondsToSelector:@selector(doubleValue)] ? @([value doubleValue]) : [NSNull null];
    case NSDateAttributeType:
        return [value isKindOfClass:[NSDate class]] ? @([value timeIntervalSinceReferenceDate]) : [NSNull null];
    case NSStringAttributeType: return [value isKindOfClass:[NSString class]] ? value : [value description];
    case NSUUIDAttributeType: return [value isKindOfClass:[NSUUID class]] ? [value UUIDString] : [value description];
    case NSURIAttributeType: return [value isKindOfClass:[NSURL class]] ? [value absoluteString] : [value description];
    default: return [value isKindOfClass:[NSData class]] ? value : [NSNull null];
    }
}

/* What a column held, as the attribute's value. */
static id attribute_value(NSAttributeDescription *a, id raw)
{
    if (!raw || raw == [NSNull null])
        return nil;
    id v = nil;
    switch ([a attributeType]) {
    case NSInteger16AttributeType: v = [NSNumber numberWithShort:(short)[raw longLongValue]]; break;
    case NSInteger32AttributeType: v = [NSNumber numberWithInt:(int)[raw longLongValue]]; break;
    case NSInteger64AttributeType: v = [NSNumber numberWithLongLong:[raw longLongValue]]; break;
    case NSBooleanAttributeType: v = [NSNumber numberWithBool:[raw longLongValue] != 0]; break;
    case NSDecimalAttributeType:
    case NSDoubleAttributeType: v = [NSNumber numberWithDouble:[raw doubleValue]]; break;
    case NSFloatAttributeType: v = [NSNumber numberWithFloat:(float)[raw doubleValue]]; break;
    case NSDateAttributeType: v = [NSDate dateWithTimeIntervalSinceReferenceDate:[raw doubleValue]]; break;
    case NSStringAttributeType: v = [raw isKindOfClass:[NSString class]] ? raw : [raw description]; break;
    case NSUUIDAttributeType: v = [[[NSUUID alloc] initWithUUIDString:[raw description]] autorelease]; break;
    case NSURIAttributeType: v = [NSURL URLWithString:[raw description]]; break;
    default: v = [raw isKindOfClass:[NSData class]] ? raw : nil; break;
    }
    return [a cd_valueFromStored:v];
}

/* The number of characters SQLite counts in a string (code points). */
static NSUInteger code_points(NSString *s)
{
    NSUInteger n = 0, len = [s length];
    for (NSUInteger i = 0; i < len; i++, n++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < len)
            i++;
    }
    return n;
}

/* ---- predicates as SQL ------------------------------------------------------------------------
 * Each piece answers its SQL (nil when it has none; the context's own
 * evaluation then decides), and says in *exact whether the SQL picks
 * exactly the rows the predicate does; otherwise it picks more. A
 * comparison is never NULL in SQL, as nothing compared with nil is true
 * in a predicate. */

typedef struct {
    NSEntityDescription *entity;
    CDSQLiteStore *store;
} SQLScope;

static NSString *const kinds_numeric = @"n", *const kinds_date = @"d", *const kinds_string = @"s";

static NSString *attribute_kind(NSAttributeDescription *a)
{
    switch ([a attributeType]) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType:
    case NSDoubleAttributeType: return kinds_numeric;
    case NSDateAttributeType: return kinds_date;
    case NSStringAttributeType: return kinds_string;
    default: return nil;
    }
}

/* A constant as an argument for a column of the kind; nil when it can't equal any value there. */
static id constant_argument(id c, NSString *kind)
{
    if (kind == kinds_numeric && [c isKindOfClass:[NSNumber class]])
        return c;
    if (kind == kinds_date && [c isKindOfClass:[NSDate class]])
        return @([c timeIntervalSinceReferenceDate]);
    if (kind == kinds_string && [c isKindOfClass:[NSString class]])
        return c;
    return nil;
}

/* An object ID for a constant, with *object set when it was a managed object. */
static NSManagedObjectID *constant_ID(id c, BOOL *object)
{
    if ([c isKindOfClass:[NSManagedObject class]]) {
        *object = YES;
        return [c objectID];
    }
    return [c isKindOfClass:[NSManagedObjectID class]] ? c : nil;
}

/* The primary key a constant ID has among the rows of root, or -1 when no row there can be it. */
static int64_t pk_in(NSManagedObjectID *oid, NSEntityDescription *root, CDSQLiteStore *store)
{
    if (!oid || [oid isTemporaryID] || [oid persistentStore] != store ||
        ![[[[oid entity] cd_root] name] isEqualToString:[root name]])
        return -1;
    return [oid cd_pk];
}

static NSArray *collection_items(id c)
{
    if ([c isKindOfClass:[NSArray class]])
        return c;
    if ([c isKindOfClass:[NSSet class]])
        return [c allObjects];
    if ([c isKindOfClass:[NSOrderedSet class]])
        return [c array];
    return nil;
}

static NSString *placeholders(NSUInteger n)
{
    NSMutableArray *q = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++)
        [q addObject:@"?"];
    return [q componentsJoinedByString:@","];
}

/* SELF, or a to-one relationship (its primary key column), against object IDs. */
static NSString *id_comparison(NSString *column, NSEntityDescription *root, NSString *op, id c, SQLScope *scope,
                               NSMutableArray *args, BOOL *exact)
{
    BOOL object = NO;
    if ([op isEqualToString:@"IN"]) {
        NSArray *items = collection_items(c);
        if (!items)
            return nil;
        NSMutableArray *pks = [NSMutableArray array];
        for (id x in items) {
            if (x == [NSNull null])
                return nil;
            int64_t pk = pk_in(constant_ID(x, &object), root, scope->store);
            if (pk >= 0)
                [pks addObject:@(pk)];
        }
        *exact = !object;
        if (![pks count])
            return @"0";
        [args addObjectsFromArray:pks];
        return [NSString stringWithFormat:@"COALESCE(%@ IN (%@), 0)", column, placeholders([pks count])];
    }
    BOOL eq = [op isEqualToString:@"=="];
    if (!eq && ![op isEqualToString:@"!="])
        return nil;
    if (!c || c == [NSNull null]) {
        *exact = YES;
        return [NSString stringWithFormat:eq ? @"%@ IS NULL" : @"%@ IS NOT NULL", column];
    }
    NSManagedObjectID *oid = constant_ID(c, &object);
    if (!oid)
        return nil;
    int64_t pk = pk_in(oid, root, scope->store);
    *exact = !object;
    if (pk < 0)
        return eq ? @"0" : @"1";
    [args addObject:@(pk)];
    return [NSString stringWithFormat:eq ? @"COALESCE(%@ = ?, 0)" : @"(%@ IS NULL OR %@ != ?)", column, column];
}

static NSString *comparison_sql(NSDictionary *s, SQLScope *scope, NSMutableArray *args, BOOL *exact)
{
    *exact = NO;
    if (![[s objectForKey:@"modifier"] isEqualToString:@"direct"] || [[s objectForKey:@"caseInsensitive"] boolValue] ||
        [[s objectForKey:@"diacriticInsensitive"] boolValue])
        return nil;
    NSDictionary *l = [s objectForKey:@"left"], *r = [s objectForKey:@"right"];
    NSString *op = [s objectForKey:@"op"];
    if ([[l objectForKey:@"kind"] isEqualToString:@"constant"] && ![[r objectForKey:@"kind"] isEqualToString:@"constant"]) {
        NSDictionary *flip = @{@"==" : @"==", @"!=" : @"!=", @"<" : @">", @">" : @"<", @"<=" : @">=", @">=" : @"<="};
        op = [flip objectForKey:op];
        if (!op)
            return nil;
        NSDictionary *t = l;
        l = r, r = t;
    }
    if (![[r objectForKey:@"kind"] isEqualToString:@"constant"])
        return nil;
    id c = [r objectForKey:@"value"];
    if (c == [NSNull null])
        c = nil;
    NSEntityDescription *root = [scope->entity cd_root];
    if ([[l objectForKey:@"kind"] isEqualToString:@"self"])
        return id_comparison(@"Z_PK", root, op, c, scope, args, exact);
    if (![[l objectForKey:@"kind"] isEqualToString:@"keypath"])
        return nil;
    NSString *key = [l objectForKey:@"value"];
    if (![key isKindOfClass:[NSString class]] || [key rangeOfString:@"."].location != NSNotFound)
        return nil;
    NSPropertyDescription *p = [scope->entity cd_propertyNamed:key];
    if (!p || [p isTransient])
        return nil;
    NSString *col = quoted(column_name(key));
    if ([p isKindOfClass:[NSRelationshipDescription class]]) {
        NSRelationshipDescription *rel = (NSRelationshipDescription *)p;
        if ([rel isToMany] || ![rel destinationEntity])
            return nil;
        return id_comparison(col, [[rel destinationEntity] cd_root], op, c, scope, args, exact);
    }
    NSString *kind = attribute_kind((NSAttributeDescription *)p);
    if (!kind)
        return nil;
    BOOL ordering = [@[ @"<", @"<=", @">", @">=" ] containsObject:op];
    if ([op isEqualToString:@"=="] || [op isEqualToString:@"!="] || ordering) {
        BOOL eq = [op isEqualToString:@"=="];
        if (!c) {
            if (ordering)
                return nil;
            *exact = YES;
            return [NSString stringWithFormat:eq ? @"%@ IS NULL" : @"%@ IS NOT NULL", col];
        }
        id arg = constant_argument(c, kind);
        if (!arg || (ordering && kind == kinds_string))
            return nil;
        [args addObject:arg];
        *exact = YES;
        if ([op isEqualToString:@"!="])
            return [NSString stringWithFormat:@"(%@ IS NULL OR %@ != ?)", col, col];
        return [NSString stringWithFormat:@"COALESCE(%@ %@ ?, 0)", col, eq ? @"=" : op];
    }
    if ([op isEqualToString:@"BETWEEN"]) {
        NSArray *pair = collection_items(c);
        if (kind == kinds_string || [pair count] != 2)
            return nil;
        id lo = constant_argument([pair objectAtIndex:0], kind), hi = constant_argument([pair objectAtIndex:1], kind);
        if (!lo || !hi)
            return nil;
        [args addObject:lo];
        [args addObject:hi];
        *exact = YES;
        return [NSString stringWithFormat:@"COALESCE(%@ BETWEEN ? AND ?, 0)", col];
    }
    if ([op isEqualToString:@"IN"]) {
        NSArray *items = collection_items(c);
        if (!items)
            return nil;
        NSMutableArray *values = [NSMutableArray array];
        for (id x in items) {
            if (x == [NSNull null])
                return nil;
            id arg = constant_argument(x, kind);
            if (arg)
                [values addObject:arg];
        }
        *exact = YES;
        if (![values count])
            return @"0";
        [args addObjectsFromArray:values];
        return [NSString stringWithFormat:@"COALESCE(%@ IN (%@), 0)", col, placeholders([values count])];
    }
    /* the string operators */
    if (kind != kinds_string || ![c isKindOfClass:[NSString class]] || ![c length])
        return nil;
    *exact = YES;
    if ([op isEqualToString:@"BEGINSWITH"]) {
        [args addObject:c];
        return [NSString stringWithFormat:@"COALESCE(instr(%@, ?) = 1, 0)", col];
    }
    if ([op isEqualToString:@"ENDSWITH"]) {
        [args addObject:@(code_points(c))];
        [args addObject:c];
        return [NSString stringWithFormat:@"COALESCE(substr(%@, -?) = ?, 0)", col];
    }
    if ([op isEqualToString:@"CONTAINS"]) {
        [args addObject:c];
        return [NSString stringWithFormat:@"COALESCE(instr(%@, ?) > 0, 0)", col];
    }
    if ([op isEqualToString:@"LIKE"] && [c rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"[\\?"]]
                                                .location == NSNotFound) {
        [args addObject:c];
        return [NSString stringWithFormat:@"COALESCE(%@ GLOB ?, 0)", col];
    }
    *exact = NO;
    return nil;
}

static NSString *predicate_sql(NSDictionary *s, SQLScope *scope, NSMutableArray *args, BOOL *exact)
{
    *exact = NO;
    if (![s isKindOfClass:[NSDictionary class]])
        return nil;
    NSString *type = [s objectForKey:@"type"];
    if ([type isEqualToString:@"value"]) {
        *exact = YES;
        return [[s objectForKey:@"value"] boolValue] ? @"1" : @"0";
    }
    if ([type isEqualToString:@"comparison"])
        return comparison_sql(s, scope, args, exact);
    NSArray *subs = [s objectForKey:@"subpredicates"];
    NSMutableArray *parts = [NSMutableArray array];
    BOOL all = YES;
    for (NSDictionary *sub in subs) {
        NSMutableArray *a = [NSMutableArray array];
        BOOL e;
        NSString *sql = predicate_sql(sub, scope, a, &e);
        if (!sql || !e)
            all = NO;
        if (!sql) {
            if ([type isEqualToString:@"and"])
                continue;
            return nil;   /* OR and NOT need every part */
        }
        if ([type isEqualToString:@"not"] && !e)
            return nil;
        [parts addObject:sql];
        [args addObjectsFromArray:a];
    }
    if ([type isEqualToString:@"not"]) {
        if ([parts count] != 1)
            return nil;
        *exact = YES;
        return [NSString stringWithFormat:@"NOT (%@)", [parts objectAtIndex:0]];
    }
    if (![parts count]) {
        if ([type isEqualToString:@"and"] && ![subs count]) {
            *exact = YES;
            return @"1";
        }
        if ([type isEqualToString:@"or"] && ![subs count]) {
            *exact = YES;
            return @"0";
        }
        return nil;
    }
    *exact = all;
    return [NSString stringWithFormat:@"(%@)", [parts componentsJoinedByString:[type isEqualToString:@"and"] ? @" AND "
                                                                                                           : @" OR "]];
}

/* ---- the store ----------------------------------------------------------------------------------- */

@implementation CDSQLiteStore {
    sqlite3 *_db;
    int _transactions;
    NSMutableDictionary *_columns;   /* table name -> NSArray of column names (after Z_PK, Z_ENT, Z_OPT) */
}

- (instancetype)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                                 configurationName:(NSString *)name
                                               URL:(NSURL *)url
                                           options:(NSDictionary *)options
{
    if ((self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options])) {
        [self cd_setType:NSSQLiteStoreType];
        _columns = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self cd_close];
    [_columns release];
    [super dealloc];
}

- (void)cd_close
{
    if (_db)
        sqlite3_close(_db);
    _db = NULL;
}

/* ---- statements ---- */

static BOOL bind_args(sqlite3_stmt *st, NSArray *args)
{
    int i = 1;
    for (id a in args) {
        if ([a isKindOfClass:[NSNumber class]]) {
            const char *t = [a objCType];
            if (*t == 'd' || *t == 'f')
                sqlite3_bind_double(st, i, [a doubleValue]);
            else
                sqlite3_bind_int64(st, i, [a longLongValue]);
        } else if ([a isKindOfClass:[NSString class]]) {
            const char *u = [a UTF8String];
            sqlite3_bind_text(st, i, u, (int)strlen(u), SQLITE_TRANSIENT);
        } else if ([a isKindOfClass:[NSData class]])
            sqlite3_bind_blob(st, i, [a bytes], (int)[a length], SQLITE_TRANSIENT);
        else
            sqlite3_bind_null(st, i);
        i++;
    }
    return YES;
}

- (NSError *)cd_sqlError:(NSString *)sql
{
    return CDError(NSSQLiteError,
                   [NSString stringWithFormat:@"SQLite error: %s", _db ? sqlite3_errmsg(_db) : "no database"],
                   sql ? @{@"NSSQLiteErrorStatement" : sql} : nil);
}

/* The rows a statement answers, each an array of NSNumber, NSString, NSData or NSNull; nil on an error. */
- (NSArray *)cd_query:(NSString *)sql args:(NSArray *)args error:(NSError **)error
{
    sqlite3_stmt *st = NULL;
    if (!_db || sqlite3_prepare_v2(_db, [sql UTF8String], -1, &st, NULL) != SQLITE_OK) {
        if (error)
            *error = [self cd_sqlError:sql];
        return nil;
    }
    bind_args(st, args);
    NSMutableArray *rows = [NSMutableArray array];
    int rc, n = sqlite3_column_count(st);
    while ((rc = sqlite3_step(st)) == SQLITE_ROW) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:n];
        for (int i = 0; i < n; i++)
            switch (sqlite3_column_type(st, i)) {
            case SQLITE_INTEGER: [row addObject:@(sqlite3_column_int64(st, i))]; break;
            case SQLITE_FLOAT: [row addObject:@(sqlite3_column_double(st, i))]; break;
            case SQLITE_TEXT:
                [row addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(st, i)] ?: @""];
                break;
            case SQLITE_BLOB:
                [row addObject:[NSData dataWithBytes:sqlite3_column_blob(st, i) length:sqlite3_column_bytes(st, i)]];
                break;
            default: [row addObject:[NSNull null]]; break;
            }
        [rows addObject:row];
    }
    if (rc != SQLITE_DONE) {
        if (error)
            *error = [self cd_sqlError:sql];
        sqlite3_finalize(st);
        return nil;
    }
    sqlite3_finalize(st);
    return rows;
}

- (BOOL)cd_run:(NSString *)sql args:(NSArray *)args error:(NSError **)error
{
    return [self cd_query:sql args:args error:error] != nil;
}

- (BOOL)cd_begin:(NSError **)error
{
    if (_transactions++ > 0)
        return YES;
    if ([self cd_run:@"BEGIN IMMEDIATE" args:nil error:error])
        return YES;
    _transactions = 0;
    return NO;
}

- (BOOL)cd_end:(BOOL)commit error:(NSError **)error
{
    if (--_transactions > 0)
        return commit;
    if (commit && [self cd_run:@"COMMIT" args:nil error:error])
        return YES;
    [self cd_run:@"ROLLBACK" args:nil error:NULL];
    return NO;
}

/* ---- the tables ---- */

- (NSManagedObjectModel *)cd_model { return [[self cd_coordinatorRef] managedObjectModel]; }

/* The columns the model wants in each table (name -> SQL type), the to-many tables, in order. */
- (void)cd_wantedTables:(NSMutableDictionary *)tables joins:(NSMutableArray *)joins
{
    for (NSEntityDescription *e in [[self cd_model] entities]) {
        NSString *t = table_name(e);
        NSMutableDictionary *cols = [tables objectForKey:t];
        if (!cols)
            [tables setObject:(cols = [NSMutableDictionary dictionary]) forKey:t];
        for (NSAttributeDescription *a in [e cd_persistentAttributes])
            [cols setObject:column_type([a attributeType]) forKey:column_name([a name])];
        for (NSRelationshipDescription *r in [e cd_persistentRelationships]) {
            if ([r isToMany]) {
                NSString *j = join_table_name(e, [r name]);
                if (![joins containsObject:j])
                    [joins addObject:j];
            } else {
                [cols setObject:@"INTEGER" forKey:column_name([r name])];
                [cols setObject:@"TEXT" forKey:entity_column_name([r name])];
            }
        }
    }
}

- (NSSet *)cd_existingColumnsOf:(NSString *)table
{
    NSMutableSet *names = [NSMutableSet set];
    for (NSArray *row in [self cd_query:[NSString stringWithFormat:@"PRAGMA table_info(%@)", quoted(table)]
                                   args:nil
                                  error:NULL])
        [names addObject:[row objectAtIndex:1]];
    return names;
}

/* Makes the tables and columns the model needs that the file lacks. */
- (BOOL)cd_makeTables:(NSError **)error
{
    NSMutableDictionary *tables = [NSMutableDictionary dictionary];
    NSMutableArray *joins = [NSMutableArray array];
    [self cd_wantedTables:tables joins:joins];
    NSArray *fixed = @[
        @"CREATE TABLE IF NOT EXISTS Z_PRIMARYKEY (Z_NAME TEXT PRIMARY KEY, Z_MAX INTEGER)",
        @"CREATE TABLE IF NOT EXISTS Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT, Z_PLIST BLOB)",
    ];
    for (NSString *sql in fixed)
        if (![self cd_run:sql args:nil error:error])
            return NO;
    for (NSString *t in [[tables allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *cols = [tables objectForKey:t];
        NSSet *have = [self cd_existingColumnsOf:t];
        NSArray *names = [[cols allKeys] sortedArrayUsingSelector:@selector(compare:)];
        if (![have count]) {
            NSMutableString *sql = [NSMutableString
                stringWithFormat:@"CREATE TABLE %@ (Z_PK INTEGER PRIMARY KEY, Z_ENT TEXT, Z_OPT INTEGER", quoted(t)];
            for (NSString *c in names)
                [sql appendFormat:@", %@ %@", quoted(c), [cols objectForKey:c]];
            [sql appendString:@")"];
            if (![self cd_run:sql args:nil error:error] ||
                ![self cd_run:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS %@ ON %@ (Z_ENT)",
                                                         quoted([t stringByAppendingString:@"_Z_ENT"]), quoted(t)]
                         args:nil
                        error:error])
                return NO;
        } else
            for (NSString *c in names)
                if (![have containsObject:c] &&
                    ![self cd_run:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", quoted(t), quoted(c),
                                                             [cols objectForKey:c]]
                             args:nil
                            error:error])
                    return NO;
    }
    for (NSString *j in joins)
        if (![self cd_run:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (Z_SRC INTEGER, Z_DST INTEGER, "
                                                     @"Z_ORD INTEGER)",
                                                     quoted(j)]
                     args:nil
                    error:error] ||
            ![self cd_run:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS %@ ON %@ (Z_SRC)",
                                                     quoted([j stringByAppendingString:@"_SRC"]), quoted(j)]
                     args:nil
                    error:error])
            return NO;
    [self cd_learnColumns];
    return YES;
}

/* The columns each table has, which is what fetches read. */
- (void)cd_learnColumns
{
    [_columns removeAllObjects];
    for (NSEntityDescription *e in [[self cd_model] entities]) {
        NSString *t = table_name(e);
        if ([_columns objectForKey:t])
            continue;
        NSMutableArray *cols = [NSMutableArray array];
        for (NSString *c in [[[self cd_existingColumnsOf:t] allObjects] sortedArrayUsingSelector:@selector(compare:)])
            if (![@[ @"Z_PK", @"Z_ENT", @"Z_OPT" ] containsObject:c])
                [cols addObject:c];
        [_columns setObject:cols forKey:t];
    }
}

/* ---- metadata ---- */

static NSData *metadata_data(NSDictionary *metadata)
{
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:metadata
                                                           format:NSPropertyListXMLFormat_v1_0
                                                          options:0
                                                            error:NULL];
    return d ?: [NSKeyedArchiver archivedDataWithRootObject:metadata];
}

static NSDictionary *metadata_from_data(id d)
{
    if (![d isKindOfClass:[NSData class]])
        return nil;
    id m = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL];
    if (![m isKindOfClass:[NSDictionary class]]) {
        @try {
            m = [NSKeyedUnarchiver unarchiveObjectWithData:d];
        } @catch (NSException *e) {
            m = nil;
        }
    }
    return [m isKindOfClass:[NSDictionary class]] ? m : nil;
}

- (BOOL)cd_hasMetadataTable
{
    return [[self cd_query:@"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'Z_METADATA'"
                      args:nil
                     error:NULL] count] > 0;
}

- (NSDictionary *)cd_readMetadata
{
    NSArray *rows = [self cd_query:@"SELECT Z_PLIST FROM Z_METADATA WHERE Z_VERSION = 1" args:nil error:NULL];
    return [rows count] ? metadata_from_data([[rows objectAtIndex:0] objectAtIndex:0]) : nil;
}

- (BOOL)cd_saveMetadata:(NSError **)error
{
    NSDictionary *m = [self metadata];
    return [self cd_run:@"INSERT OR REPLACE INTO Z_METADATA (Z_VERSION, Z_UUID, Z_PLIST) VALUES (1, ?, ?)"
                   args:@[ [self identifier] ?: @"", metadata_data(m) ]
                  error:error];
}

- (void)cd_writeMetadata
{
    if (_db && ![self isReadOnly])
        [self cd_saveMetadata:NULL];
}

static sqlite3 *open_file(NSString *path, BOOL readOnly)
{
    sqlite3 *db = NULL;
    int flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX;
    if (sqlite3_open_v2([path fileSystemRepresentation], &db, flags, NULL) != SQLITE_OK) {
        if (db)
            sqlite3_close(db);
        return NULL;
    }
    sqlite3_busy_timeout(db, 30000);
    return db;
}

+ (NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
        CDFail(error, NSFileReadNoSuchFileError, [NSString stringWithFormat:@"There is no store at %@.", [url path]],
               nil);
        return nil;
    }
    CDSQLiteStore *s = [[[CDSQLiteStore alloc] initWithPersistentStoreCoordinator:nil
                                                                configurationName:nil
                                                                              URL:url
                                                                          options:nil] autorelease];
    s->_db = open_file([url path], YES);
    NSDictionary *m = s->_db && [s cd_hasMetadataTable] ? [s cd_readMetadata] : nil;
    if (!m)
        CDFail(error, NSPersistentStoreInvalidTypeError, @"The file isn't a Core Data SQLite store.", nil);
    return m;
}

+ (BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error
{
    CDSQLiteStore *s = [[[CDSQLiteStore alloc] initWithPersistentStoreCoordinator:nil
                                                                configurationName:nil
                                                                              URL:url
                                                                          options:nil] autorelease];
    s->_db = open_file([url path], NO);
    if (!s->_db || ![s cd_hasMetadataTable])
        return CDFail(error, NSPersistentStoreInvalidTypeError, @"The file isn't a Core Data SQLite store.", nil);
    if ([metadata objectForKey:NSStoreUUIDKey])
        [s setIdentifier:[metadata objectForKey:NSStoreUUIDKey]];
    [s setMetadata:metadata];
    return [s cd_saveMetadata:error];
}

/* ---- opening ---- */

- (BOOL)cd_load:(NSError **)error
{
    NSString *path = [[self URL] path];
    BOOL readOnly = [self isReadOnly];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (readOnly && ![fm fileExistsAtPath:path])
        return CDFail(error, NSPersistentStoreOpenError,
                      [NSString stringWithFormat:@"There is no store at %@ to open read-only.", path], nil);
    if (!readOnly)
        [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:NULL];
    _db = open_file(path, readOnly);
    if (!_db)
        return CDFail(error, NSPersistentStoreOpenError, [NSString stringWithFormat:@"Can't open %@.", path], nil);
    NSNumber *timeout = [[self options] objectForKey:NSPersistentStoreTimeoutOption];
    if ([timeout doubleValue] > 0)
        sqlite3_busy_timeout(_db, (int)([timeout doubleValue] * 1000));
    NSDictionary *pragmas = [[self options] objectForKey:NSSQLitePragmasOption];
    for (NSString *name in pragmas) {
        id v = [pragmas objectForKey:name];
        if (v != [NSNull null])
            [self cd_run:[NSString stringWithFormat:@"PRAGMA %@ = %@", name, v] args:nil error:NULL];
    }
    NSError *err = nil;
    NSArray *probe = [self cd_query:@"SELECT count(*) FROM sqlite_master" args:nil error:&err];
    if (!probe) {
        [self cd_close];
        return CDFail(error, NSPersistentStoreInvalidTypeError,
                      [NSString stringWithFormat:@"%@ isn't an SQLite file.", path], nil);
    }
    if (![self cd_hasMetadataTable]) {
        if ([[[probe objectAtIndex:0] objectAtIndex:0] longLongValue] > 0) {
            [self cd_close];
            return CDFail(error, NSPersistentStoreIncompatibleSchemaError,
                          [NSString stringWithFormat:@"%@ is an SQLite file that Ferry's Core Data didn't make.", path],
                          nil);
        }
        if (readOnly) {
            [self cd_close];
            return CDFail(error, NSPersistentStoreOpenError, @"The store is empty and was opened read-only.", nil);
        }
        [self cd_stampMetadata];
        if (![self cd_begin:error])
            return NO;
        BOOL ok = [self cd_makeTables:error] && [self cd_saveMetadata:error];
        return [self cd_end:ok error:error];
    }
    NSDictionary *meta = [self cd_readMetadata];
    if (!meta || ![[meta objectForKey:NSStoreTypeKey] isEqual:NSSQLiteStoreType]) {
        [self cd_close];
        return CDFail(error, NSPersistentStoreInvalidTypeError, @"The store's metadata can't be read.", nil);
    }
    NSMutableArray *added = [NSMutableArray array];
    NSManagedObjectModel *model = [self cd_model];
    if (!CDCheckSchema(model, meta, [self options], added, error)) {
        [self cd_close];
        return NO;
    }
    if ([meta objectForKey:NSStoreUUIDKey])
        [self setIdentifier:[meta objectForKey:NSStoreUUIDKey]];
    [self setMetadata:meta];
    BOOL changed = [added count] || ![model isConfiguration:nil compatibleWithStoreMetadata:meta];
    if (!changed || readOnly) {
        if (changed) {
            [self cd_close];
            return CDFail(error, NSMigrationError, @"A read-only store can't be migrated.", nil);
        }
        [self cd_learnColumns];
        return YES;
    }
    /* a lightweight migration: new tables and columns, new attributes' default values */
    if (![self cd_begin:error])
        return NO;
    BOOL ok = [self cd_makeTables:error];
    NSDictionary *entities = [model entitiesByName];
    for (NSDictionary *change in added) {
        if (!ok || ![[change objectForKey:@"kind"] isEqualToString:@"attribute"])
            continue;
        NSEntityDescription *e = [entities objectForKey:[change objectForKey:@"entity"]];
        NSAttributeDescription *a = (NSAttributeDescription *)[e cd_propertyNamed:[change objectForKey:@"name"]];
        if (![a defaultValue])
            continue;
        NSArray *names = [e cd_selfAndSubentityNames];
        NSMutableArray *args = [NSMutableArray arrayWithObject:raw_value(a, [a defaultValue])];
        [args addObjectsFromArray:names];
        ok = [self cd_run:[NSString stringWithFormat:@"UPDATE %@ SET %@ = ? WHERE %@ IS NULL AND Z_ENT IN (%@)",
                                                     quoted(table_name(e)), quoted(column_name([a name])),
                                                     quoted(column_name([a name])), placeholders([names count])]
                     args:args
                    error:error];
    }
    if (ok) {
        [self cd_stampMetadata];
        ok = [self cd_saveMetadata:error];
    }
    if (![self cd_end:ok error:error]) {
        [self cd_close];
        return NO;
    }
    return YES;
}

/* ---- reading ---- */

- (NSString *)cd_selectListFor:(NSString *)table
{
    NSMutableArray *cols = [NSMutableArray arrayWithObjects:@"Z_PK", @"Z_ENT", @"Z_OPT", nil];
    for (NSString *c in [_columns objectForKey:table])
        [cols addObject:quoted(c)];
    return [cols componentsJoinedByString:@", "];
}

/* A row (as cd_query answers it, from cd_selectListFor:) as a snapshot; nil for an entity the model lacks. */
- (CDSnapshot *)cd_snapshotFromRow:(NSArray *)row table:(NSString *)table
{
    NSDictionary *entities = [[self cd_model] entitiesByName];
    NSEntityDescription *e = [entities objectForKey:[row objectAtIndex:1]];
    if (!e)
        return nil;
    NSArray *cols = [_columns objectForKey:table];
    NSMutableDictionary *byColumn = [NSMutableDictionary dictionaryWithCapacity:[cols count]];
    for (NSUInteger i = 0; i < [cols count]; i++)
        [byColumn setObject:[row objectAtIndex:i + 3] forKey:[cols objectAtIndex:i]];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSAttributeDescription *a in [e cd_persistentAttributes]) {
        id v = attribute_value(a, [byColumn objectForKey:column_name([a name])]);
        if (v)
            [values setObject:v forKey:[a name]];
    }
    for (NSRelationshipDescription *r in [e cd_persistentRelationships]) {
        if ([r isToMany])
            continue;
        id pk = [byColumn objectForKey:column_name([r name])];
        NSEntityDescription *d = [entities objectForKey:[byColumn objectForKey:entity_column_name([r name])]];
        if (d && [pk isKindOfClass:[NSNumber class]])
            [values setObject:[NSManagedObjectID cd_IDForEntity:d store:self pk:[pk longLongValue]] forKey:[r name]];
    }
    NSManagedObjectID *oid = [NSManagedObjectID cd_IDForEntity:e store:self pk:[[row objectAtIndex:0] longLongValue]];
    return [CDSnapshot snapshotWithID:oid values:values version:[[row objectAtIndex:2] longLongValue]];
}

/* The WHERE clause of a query, its arguments, and whether it is exact. */
- (NSString *)cd_whereFor:(CDQuery *)q args:(NSMutableArray *)args exact:(BOOL *)exact
{
    NSArray *names = q->entityNames;
    [args addObjectsFromArray:names];
    NSString *where = [NSString stringWithFormat:@"Z_ENT IN (%@)", placeholders([names count])];
    NSPredicate *p = [q->request predicate];
    *exact = YES;
    if (p) {
        SQLScope scope = {q->entity, self};
        NSMutableArray *pa = [NSMutableArray array];
        NSString *sql = predicate_sql([p _ferryStructure], &scope, pa, exact);
        if (sql) {
            where = [NSString stringWithFormat:@"%@ AND %@", where, sql];
            [args addObjectsFromArray:pa];
        } else
            *exact = NO;
    }
    return where;
}

/* ORDER BY for the sort descriptors, when SQL sorts them as the context would; nil otherwise. */
- (NSString *)cd_orderFor:(CDQuery *)q
{
    NSMutableArray *terms = [NSMutableArray array];
    for (NSSortDescriptor *sd in [q->request sortDescriptors]) {
        NSString *key = [sd key];
        if (!key || [key rangeOfString:@"."].location != NSNotFound || [sd comparator] ||
            ([sd selector] && [sd selector] != @selector(compare:)))
            return nil;
        NSPropertyDescription *p = [q->entity cd_propertyNamed:key];
        if (![p isKindOfClass:[NSAttributeDescription class]] || [p isTransient])
            return nil;
        NSString *kind = attribute_kind((NSAttributeDescription *)p);
        if (kind != kinds_numeric && kind != kinds_date &&
            [(NSAttributeDescription *)p attributeType] != NSFloatAttributeType)
            return nil;
        [terms addObject:[NSString stringWithFormat:@"%@ %@", quoted(column_name(key)), [sd ascending] ? @"ASC" : @"DESC"]];
    }
    [terms addObject:@"Z_PK"];
    return [terms componentsJoinedByString:@", "];
}

- (NSArray *)cd_rowsForQuery:(CDQuery *)q limited:(BOOL *)limited
{
    if (limited)
        *limited = NO;
    NSString *table = table_name(q->entity);
    NSMutableArray *args = [NSMutableArray array];
    BOOL exact;
    NSString *where = [self cd_whereFor:q args:args exact:&exact];
    NSString *order = [self cd_orderFor:q];
    q->exact = exact;
    NSUInteger lim = [q->request fetchLimit], off = [q->request fetchOffset];
    NSMutableString *sql = [NSMutableString
        stringWithFormat:@"SELECT %@ FROM %@ WHERE %@ ORDER BY %@", [self cd_selectListFor:table], quoted(table), where,
                         order ?: @"Z_PK"];
    if (q->storeLimit && exact && order && (lim || off)) {
        [sql appendString:@" LIMIT ? OFFSET ?"];
        [args addObject:@(lim ? (long long)lim : -1LL)];
        [args addObject:@((long long)off)];
        if (limited)
            *limited = YES;
    }
    NSError *err = nil;
    NSArray *rows = [self cd_query:sql args:args error:&err];
    if (!rows) {
        CDWarnOnce([@"sqlfetch:" stringByAppendingString:[err localizedDescription] ?: @""],
                   [NSString stringWithFormat:@"Ferry: Core Data's SQLite fetch failed: %@", [err localizedDescription]]);
        return @[];
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:[rows count]];
    for (NSArray *row in rows) {
        CDSnapshot *s = [self cd_snapshotFromRow:row table:table];
        if (s)
            [out addObject:s];
    }
    return out;
}

- (NSUInteger)cd_countForQuery:(CDQuery *)q
{
    NSMutableArray *args = [NSMutableArray array];
    BOOL exact;
    NSString *where = [self cd_whereFor:q args:args exact:&exact];
    if (!exact)
        return NSNotFound;
    NSUInteger lim = [q->request fetchLimit], off = [q->request fetchOffset];
    [args addObject:@(lim ? (long long)lim : -1LL)];
    [args addObject:@((long long)off)];
    NSArray *rows = [self cd_query:[NSString stringWithFormat:@"SELECT count(*) FROM (SELECT Z_PK FROM %@ WHERE %@ "
                                                              @"LIMIT ? OFFSET ?)",
                                                              quoted(table_name(q->entity)), where]
                              args:args
                             error:NULL];
    return [rows count] ? (NSUInteger)[[[rows objectAtIndex:0] objectAtIndex:0] longLongValue] : NSNotFound;
}

- (CDSnapshot *)cd_rowForID:(NSManagedObjectID *)oid
{
    if (!_db || [oid isTemporaryID])
        return nil;
    NSString *table = table_name([oid entity]);
    NSArray *rows = [self cd_query:[NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE Z_PK = ?",
                                                              [self cd_selectListFor:table], quoted(table)]
                              args:@[ @([oid cd_pk]) ]
                             error:NULL];
    if (![rows count] || ![[[oid entity] cd_selfAndSubentityNames] containsObject:[[rows objectAtIndex:0] objectAtIndex:1]])
        return nil;
    return [self cd_snapshotFromRow:[rows objectAtIndex:0] table:table];
}

- (NSArray *)cd_relatedIDsForID:(NSManagedObjectID *)oid key:(NSString *)key
{
    NSRelationshipDescription *r = (NSRelationshipDescription *)[[oid entity] cd_propertyNamed:key];
    if (!_db || ![r isKindOfClass:[NSRelationshipDescription class]] || ![r isToMany] || ![r destinationEntity])
        return @[];
    NSString *sql = [NSString stringWithFormat:@"SELECT j.Z_DST, d.Z_ENT FROM %@ j JOIN %@ d ON d.Z_PK = j.Z_DST "
                                               @"WHERE j.Z_SRC = ? ORDER BY j.Z_ORD, j.Z_DST",
                                               quoted(join_table_name([oid entity], key)),
                                               quoted(table_name([r destinationEntity]))];
    NSArray *rows = [self cd_query:sql args:@[ @([oid cd_pk]) ] error:NULL];
    NSDictionary *entities = [[self cd_model] entitiesByName];
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:[rows count]];
    for (NSArray *row in rows) {
        NSEntityDescription *d = [entities objectForKey:[row objectAtIndex:1]];
        if (d)
            [ids addObject:[NSManagedObjectID cd_IDForEntity:d store:self pk:[[row objectAtIndex:0] longLongValue]]];
    }
    return ids;
}

/* ---- writing ---- */

- (int64_t)cd_reservePKs:(NSUInteger)count forEntity:(NSEntityDescription *)root
{
    NSString *name = [[root cd_root] name];
    if (![self cd_begin:NULL])
        return 0;
    [self cd_run:@"INSERT OR IGNORE INTO Z_PRIMARYKEY (Z_NAME, Z_MAX) VALUES (?, 0)" args:@[ name ] error:NULL];
    NSArray *rows = [self cd_query:@"SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = ?" args:@[ name ] error:NULL];
    int64_t first = [rows count] ? [[[rows objectAtIndex:0] objectAtIndex:0] longLongValue] + 1 : 1;
    BOOL ok = [self cd_run:@"UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = ?"
                      args:@[ @(first + (int64_t)count - 1), name ]
                     error:NULL];
    [self cd_end:ok error:NULL];
    return ok ? first : 0;
}

- (BOOL)cd_writeToMany:(NSRelationshipDescription *)r of:(NSManagedObjectID *)oid ids:(id)ids error:(NSError **)error
{
    NSString *j = quoted(join_table_name([oid entity], [r name]));
    if (![self cd_run:[NSString stringWithFormat:@"DELETE FROM %@ WHERE Z_SRC = ?", j] args:@[ @([oid cd_pk]) ] error:error])
        return NO;
    NSInteger i = 0;
    for (NSManagedObjectID *d in collection_items(ids))
        if ([d isKindOfClass:[NSManagedObjectID class]] && ![d isTemporaryID] &&
            ![self cd_run:[NSString stringWithFormat:@"INSERT INTO %@ (Z_SRC, Z_DST, Z_ORD) VALUES (?, ?, ?)", j]
                     args:@[ @([oid cd_pk]), @([d cd_pk]), @(i++) ]
                    error:error])
            return NO;
    return YES;
}

/* Writes an object's values: the columns of attributes and to-ones, then its to-many tables. */
- (BOOL)cd_writeValues:(NSDictionary *)values of:(NSManagedObjectID *)oid insert:(BOOL)insert version:(int64_t)version
                 error:(NSError **)error
{
    NSEntityDescription *e = [oid entity];
    NSMutableArray *cols = [NSMutableArray array], *args = [NSMutableArray array];
    NSMutableArray *manys = [NSMutableArray array];
    for (NSString *k in values) {
        NSPropertyDescription *p = [e cd_propertyNamed:k];
        id v = [values objectForKey:k];
        if (!p || [p isTransient])
            continue;
        if ([p isKindOfClass:[NSAttributeDescription class]]) {
            [cols addObject:column_name(k)];
            [args addObject:raw_value((NSAttributeDescription *)p, v)];
        } else if ([(NSRelationshipDescription *)p isToMany])
            [manys addObject:p];
        else {
            BOOL set = [v isKindOfClass:[NSManagedObjectID class]] && ![v isTemporaryID];
            [cols addObject:column_name(k)];
            [args addObject:set ? (id)@([v cd_pk]) : (id)[NSNull null]];
            [cols addObject:entity_column_name(k)];
            [args addObject:set ? (id)[[v entity] name] : (id)[NSNull null]];
        }
    }
    NSString *t = quoted(table_name(e));
    NSString *sql;
    if (insert) {
        NSMutableArray *q = [NSMutableArray arrayWithObjects:@"Z_PK", @"Z_ENT", @"Z_OPT", nil];
        for (NSString *c in cols)
            [q addObject:quoted(c)];
        [args insertObject:@(version) atIndex:0];
        [args insertObject:[e name] atIndex:0];
        [args insertObject:@([oid cd_pk]) atIndex:0];
        sql = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)", t, [q componentsJoinedByString:@", "],
                                         placeholders([q count])];
    } else {
        NSMutableArray *sets = [NSMutableArray arrayWithObject:@"Z_OPT = ?"];
        for (NSString *c in cols)
            [sets addObject:[NSString stringWithFormat:@"%@ = ?", quoted(c)]];
        [args insertObject:@(version) atIndex:0];
        [args addObject:@([oid cd_pk])];
        sql = [NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE Z_PK = ?", t, [sets componentsJoinedByString:@", "]];
    }
    if (![self cd_run:sql args:args error:error])
        return NO;
    for (NSRelationshipDescription *r in manys)
        if (![self cd_writeToMany:r of:oid ids:[values objectForKey:[r name]] error:error])
            return NO;
    return YES;
}

- (BOOL)cd_deleteRow:(NSManagedObjectID *)oid error:(NSError **)error
{
    NSEntityDescription *e = [oid entity];
    if (![self cd_run:[NSString stringWithFormat:@"DELETE FROM %@ WHERE Z_PK = ?", quoted(table_name(e))]
                 args:@[ @([oid cd_pk]) ]
                error:error])
        return NO;
    for (NSRelationshipDescription *r in [e cd_persistentRelationships])
        if ([r isToMany] &&
            ![self cd_run:[NSString stringWithFormat:@"DELETE FROM %@ WHERE Z_SRC = ?", quoted(join_table_name(e, [r name]))]
                     args:@[ @([oid cd_pk]) ]
                    error:error])
            return NO;
    return YES;
}

- (BOOL)cd_apply:(CDChangeSet *)set error:(NSError **)error
{
    if ([self isReadOnly])
        return CDFail(error, NSPersistentStoreSaveError, @"The store is read-only.", nil);
    if (![self cd_begin:error])
        return NO;
    BOOL ok = CDResolveConflicts(set,
                                 ^CDSnapshot *(NSManagedObjectID *oid) {
                                     return [self cd_rowForID:oid];
                                 },
                                 error);
    NSMutableDictionary *maxPK = [NSMutableDictionary dictionary];
    for (CDChange *c in set->inserted) {
        if (!ok)
            break;
        ok = [self cd_writeValues:c->values of:c->oid insert:YES version:1 error:error];
        [set->versions setObject:@1 forKey:c->oid];
        NSString *root = [[[c->oid entity] cd_root] name];
        if ([[maxPK objectForKey:root] longLongValue] < [c->oid cd_pk])
            [maxPK setObject:@([c->oid cd_pk]) forKey:root];
    }
    for (NSString *root in maxPK)
        if (ok) {
            [self cd_run:@"INSERT OR IGNORE INTO Z_PRIMARYKEY (Z_NAME, Z_MAX) VALUES (?, 0)" args:@[ root ] error:NULL];
            ok = [self cd_run:@"UPDATE Z_PRIMARYKEY SET Z_MAX = max(Z_MAX, ?) WHERE Z_NAME = ?"
                         args:@[ [maxPK objectForKey:root], root ]
                        error:error];
        }
    for (CDChange *c in set->updated) {
        if (!ok)
            break;
        CDSnapshot *now = [self cd_rowForID:c->oid];
        if (!now)
            continue;
        int64_t version = now->version + 1;
        ok = [self cd_writeValues:c->values of:c->oid insert:NO version:version error:error];
        [set->versions setObject:@(version) forKey:c->oid];
    }
    for (CDChange *c in set->deleted) {
        if (!ok)
            break;
        ok = [self cd_deleteRow:c->oid error:error];
    }
    return [self cd_end:ok error:error];
}

/* ---- the batch requests ---- */

- (NSArray *)cd_batchDeleteIDs:(NSArray *)ids error:(NSError **)error
{
    if ([self isReadOnly]) {
        CDFail(error, NSPersistentStoreSaveError, @"The store is read-only.", nil);
        return nil;
    }
    if (![self cd_begin:error])
        return nil;
    NSMutableArray *queue = [NSMutableArray array], *deleted = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSManagedObjectID *oid in ids)
        if ([oid persistentStore] == self && ![seen containsObject:oid] && [self cd_rowForID:oid]) {
            [seen addObject:oid];
            [queue addObject:oid];
        }
    BOOL ok = YES;
    while (ok && [queue count]) {
        NSManagedObjectID *oid = [[[queue objectAtIndex:0] retain] autorelease];
        [queue removeObjectAtIndex:0];
        CDSnapshot *row = [self cd_rowForID:oid];
        if (!row)
            continue;
        NSEntityDescription *e = [oid entity];
        for (NSRelationshipDescription *r in [e cd_persistentRelationships]) {
            NSArray *related = [r isToMany] ? [self cd_relatedIDsForID:oid key:[r name]]
                               : [row->values objectForKey:[r name]] ? @[ [row->values objectForKey:[r name]] ]
                                                                     : @[];
            NSMutableArray *live = [NSMutableArray array];
            for (NSManagedObjectID *d in related)
                if (![seen containsObject:d] && [self cd_rowForID:d])
                    [live addObject:d];
            if ([r deleteRule] == NSDenyDeleteRule && [live count]) {
                ok = CDFail(error, NSValidationRelationshipDeniedDeleteError,
                            [NSString stringWithFormat:@"%@'s relationship %@ denies the delete.", [e name], [r name]],
                            @{NSValidationKeyErrorKey : [r name]});
                break;
            }
            if ([r deleteRule] == NSCascadeDeleteRule)
                for (NSManagedObjectID *d in live) {
                    [seen addObject:d];
                    [queue addObject:d];
                }
            NSRelationshipDescription *inv = [r inverseRelationship];
            if (!inv || [inv isTransient] || ![live count])
                continue;
            /* the other side forgets the object */
            for (NSManagedObjectID *d in live) {
                NSString *dt = quoted(table_name([d entity]));
                if ([inv isToMany])
                    ok = [self cd_run:[NSString stringWithFormat:@"DELETE FROM %@ WHERE Z_SRC = ? AND Z_DST = ?",
                                                                 quoted(join_table_name([d entity], [inv name]))]
                                 args:@[ @([d cd_pk]), @([oid cd_pk]) ]
                                error:error];
                else
                    ok = [self cd_run:[NSString stringWithFormat:@"UPDATE %@ SET %@ = NULL, %@ = NULL WHERE Z_PK = ? AND %@ = ?",
                                                                 dt, quoted(column_name([inv name])),
                                                                 quoted(entity_column_name([inv name])),
                                                                 quoted(column_name([inv name]))]
                                 args:@[ @([d cd_pk]), @([oid cd_pk]) ]
                                error:error];
                if (ok)
                    ok = [self cd_run:[NSString stringWithFormat:@"UPDATE %@ SET Z_OPT = Z_OPT + 1 WHERE Z_PK = ?", dt]
                                 args:@[ @([d cd_pk]) ]
                                error:error];
                if (!ok)
                    break;
            }
            if (!ok)
                break;
        }
        if (ok)
            ok = [self cd_deleteRow:oid error:error];
        if (ok)
            [deleted addObject:oid];
    }
    return [self cd_end:ok error:error] ? deleted : nil;
}

- (NSArray *)cd_batchUpdateIDs:(NSArray *)ids values:(NSDictionary *)values error:(NSError **)error
{
    if ([self isReadOnly]) {
        CDFail(error, NSPersistentStoreSaveError, @"The store is read-only.", nil);
        return nil;
    }
    if (![self cd_begin:error])
        return nil;
    NSMutableArray *updated = [NSMutableArray array];
    BOOL ok = YES;
    for (NSManagedObjectID *oid in ids) {
        if ([oid persistentStore] != self)
            continue;
        NSEntityDescription *e = [oid entity];
        NSMutableArray *sets = [NSMutableArray arrayWithObject:@"Z_OPT = Z_OPT + 1"], *args = [NSMutableArray array];
        for (id key in values) {
            NSString *name = [key isKindOfClass:[NSPropertyDescription class]] ? [key name] : key;
            NSPropertyDescription *p = [e cd_propertyNamed:name];
            if (![p isKindOfClass:[NSAttributeDescription class]] || [p isTransient]) {
                ok = CDFail(error, NSPersistentStoreOperationError,
                            [NSString stringWithFormat:@"A batch update can only set attributes, not %@.%@.", [e name],
                                                       name],
                            nil);
                break;
            }
            id v = [values objectForKey:key];
            if ([v respondsToSelector:@selector(constantValue)])
                v = [v performSelector:@selector(constantValue)];
            [sets addObject:[NSString stringWithFormat:@"%@ = ?", quoted(column_name(name))]];
            [args addObject:raw_value((NSAttributeDescription *)p, v == [NSNull null] ? nil : v)];
        }
        if (!ok)
            break;
        [args addObject:@([oid cd_pk])];
        ok = [self cd_run:[NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE Z_PK = ?", quoted(table_name(e)),
                                                     [sets componentsJoinedByString:@", "]]
                     args:args
                    error:error];
        if (!ok)
            break;
        [updated addObject:oid];
    }
    return [self cd_end:ok error:error] ? updated : nil;
}
@end
