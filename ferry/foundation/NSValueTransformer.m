/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSValueTransformer, which turns one value into another
 * (used by Cocoa bindings and by apps directly), with the named
 * transformers Foundation provides. Written from Apple's public
 * documentation; no Apple code was used. */
#import "FInternal.h"

NSString *const NSNegateBooleanTransformerName = @"NSNegateBoolean";
NSString *const NSIsNilTransformerName = @"NSIsNil";
NSString *const NSIsNotNilTransformerName = @"NSIsNotNil";
NSString *const NSUnarchiveFromDataTransformerName = @"NSUnarchiveFromData";
NSString *const NSKeyedUnarchiveFromDataTransformerName = @"NSKeyedUnarchiveFromData";
NSString *const NSSecureUnarchiveFromDataTransformerName = @"NSSecureUnarchiveFromData";

@interface FNegateBooleanTransformer : NSValueTransformer
@end
@interface FIsNilTransformer : NSValueTransformer {
@public
    BOOL _not;
}
@end

static NSMutableDictionary *named; /* under named_lock, as any thread may use it */
static os_unfair_lock named_lock = OS_UNFAIR_LOCK_INIT;

static void make_named(void)
{
    named = [[NSMutableDictionary alloc] init];
    [named setObject:[[FNegateBooleanTransformer new] autorelease] forKey:NSNegateBooleanTransformerName];
    FIsNilTransformer *isNil = [[FIsNilTransformer new] autorelease], *notNil = [[FIsNilTransformer new] autorelease];
    notNil->_not = YES;
    [named setObject:isNil forKey:NSIsNilTransformerName];
    [named setObject:notNil forKey:NSIsNotNilTransformerName];
    id secure = [[NSSecureUnarchiveFromDataTransformer new] autorelease];
    [named setObject:secure forKey:NSSecureUnarchiveFromDataTransformerName];
    [named setObject:secure forKey:NSKeyedUnarchiveFromDataTransformerName];
    [named setObject:secure forKey:NSUnarchiveFromDataTransformerName];
}
static void setup_named(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      make_named();
    });
}

@implementation NSValueTransformer
+ (void)setValueTransformer:(NSValueTransformer *)transformer forName:(NSValueTransformerName)name
{
    setup_named();
    if (!name)
        return;
    os_unfair_lock_lock(&named_lock);
    if (transformer)
        [named setObject:transformer forKey:name];
    else
        [named removeObjectForKey:name];
    os_unfair_lock_unlock(&named_lock);
}
+ (NSValueTransformer *)valueTransformerForName:(NSValueTransformerName)name
{
    setup_named();
    os_unfair_lock_lock(&named_lock);
    NSValueTransformer *t = name ? [[[named objectForKey:name] retain] autorelease] : nil;
    os_unfair_lock_unlock(&named_lock);
    if (!t && name) {
        /* A class of that name made on first use, as on a Mac. */
        Class cls = NSClassFromString(name);
        if ([cls isSubclassOfClass:[NSValueTransformer class]]) {
            NSValueTransformer *made = [[cls new] autorelease];
            os_unfair_lock_lock(&named_lock);
            t = [named objectForKey:name];
            if (!t) {
                [named setObject:made forKey:name];
                t = made;
            }
            os_unfair_lock_unlock(&named_lock);
        }
    }
    return t;
}
+ (NSArray *)valueTransformerNames
{
    setup_named();
    os_unfair_lock_lock(&named_lock);
    NSArray *names = [named allKeys];
    os_unfair_lock_unlock(&named_lock);
    return names;
}
+ (Class)transformedValueClass { return [NSObject class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value { return value; }
- (id)reverseTransformedValue:(id)value
{
    if (![[self class] allowsReverseTransformation])
        FRaise(NSInvalidArgumentException, @"%@ doesn't allow reverse transformation", [self class]);
    return [self transformedValue:value];
}
@end

@implementation FNegateBooleanTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
- (id)transformedValue:(id)value { return [NSNumber numberWithBool:![value boolValue]]; }
@end

@implementation FIsNilTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value { return [NSNumber numberWithBool:_not ? value != nil : value == nil]; }
@end

/* Data to the object archived in it, and back. */
@implementation NSSecureUnarchiveFromDataTransformer
+ (NSArray *)allowedTopLevelClasses
{
    return [NSArray arrayWithObjects:[NSArray class], [NSDictionary class], [NSSet class], [NSString class],
                                     [NSNumber class], [NSDate class], [NSData class], [NSURL class], [NSNull class],
                                     nil];
}
+ (Class)transformedValueClass { return [NSData class]; }
- (id)transformedValue:(id)value
{
    if (![value isKindOfClass:[NSData class]])
        return nil;
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:value error:NULL];
    [u setRequiresSecureCoding:NO];
    id obj = [[u decodeObjectForKey:NSKeyedArchiveRootObjectKey] retain]; /* the unarchiver holds what it made */
    [u release];
    return [obj autorelease];
}
- (id)reverseTransformedValue:(id)value
{
    return value ? [NSKeyedArchiver archivedDataWithRootObject:value requiringSecureCoding:NO error:NULL] : nil;
}
@end
