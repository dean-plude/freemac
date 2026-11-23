/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSController and NSUserDefaultsController, as Apple's public
 * documentation describes them: a controller of the user's defaults whose
 * "values" proxy reads and writes them by key (values.someKey), applied at
 * once by default, or kept until save: (revert: drops them). Observers of
 * values.someKey hear of changes made through the proxy. Apps subclass it
 * for their preferences (Gas Mask does). No Apple code was used. */
#import "AInternal.h"

@implementation NSController
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (BOOL)commitEditing { return YES; }
- (void)discardEditing {}
- (BOOL)isEditing { return NO; }
- (void)objectDidBeginEditing:(id)editor {}
- (void)objectDidEndEditing:(id)editor {}
@end

/* The values proxy: each key is a default. */
@interface AUserDefaultsValues : NSObject {
@public
    NSUserDefaultsController *controller;   /* not retained: it owns us */
}
@end

@implementation NSUserDefaultsController {
    NSUserDefaults *_defaults;
    NSDictionary *_initialValues;
    NSMutableDictionary *_pending;
    AUserDefaultsValues *_values;
    BOOL _appliesImmediately;
}
+ (NSUserDefaultsController *)sharedUserDefaultsController
{
    static NSUserDefaultsController *shared;
    if (!shared)
        shared = [[NSUserDefaultsController alloc] initWithDefaults:nil initialValues:nil];
    return shared;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults initialValues:(NSDictionary *)initialValues
{
    if ((self = [super init])) {
        _defaults = [(defaults ?: [NSUserDefaults standardUserDefaults]) retain];
        _initialValues = [initialValues copy];
        _pending = [[NSMutableDictionary alloc] init];
        _values = [[AUserDefaultsValues alloc] init];
        _values->controller = self;
        _appliesImmediately = YES;
    }
    return self;
}
- (instancetype)init { return [self initWithDefaults:nil initialValues:nil]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self initWithDefaults:nil initialValues:nil];
    if ([coder containsValueForKey:@"NSAppliesImmediately"])
        _appliesImmediately = [coder decodeBoolForKey:@"NSAppliesImmediately"];
    return self;
}
- (void)dealloc
{
    [_defaults release];
    [_initialValues release];
    [_pending release];
    [_values release];
    [super dealloc];
}
- (NSUserDefaults *)defaults { return _defaults; }
- (id)values { return _values; }
- (NSDictionary *)initialValues { return _initialValues; }
- (void)setInitialValues:(NSDictionary *)v
{
    [_initialValues release];
    _initialValues = [v copy];
}
- (BOOL)appliesImmediately { return _appliesImmediately; }
- (void)setAppliesImmediately:(BOOL)yes { _appliesImmediately = yes; }
- (BOOL)hasUnappliedChanges { return [_pending count] > 0; }
- (id)_valueForKey:(NSString *)key
{
    id v = [_pending objectForKey:key];
    if (v)
        return v == [NSNull null] ? nil : v;
    v = [_defaults objectForKey:key];
    return v ?: [_initialValues objectForKey:key];
}
- (void)_setValue:(id)value forKey:(NSString *)key
{
    [self willChangeValueForKey:@"values"];
    if (_appliesImmediately) {
        if (value)
            [_defaults setObject:value forKey:key];
        else
            [_defaults removeObjectForKey:key];
    } else
        [_pending setObject:value ?: [NSNull null] forKey:key];
    [self didChangeValueForKey:@"values"];
}
- (void)save:(id)sender
{
    for (NSString *key in _pending) {
        id v = [_pending objectForKey:key];
        if (v == [NSNull null])
            [_defaults removeObjectForKey:key];
        else
            [_defaults setObject:v forKey:key];
    }
    [_pending removeAllObjects];
}
- (void)revert:(id)sender
{
    [self willChangeValueForKey:@"values"];
    [_pending removeAllObjects];
    [self didChangeValueForKey:@"values"];
}
- (void)revertToInitialValues:(id)sender
{
    [self willChangeValueForKey:@"values"];
    for (NSString *key in _initialValues)
        [_pending setObject:[_initialValues objectForKey:key] forKey:key];
    if (_appliesImmediately)
        [self save:sender];
    [self didChangeValueForKey:@"values"];
}
@end

@implementation AUserDefaultsValues
- (id)valueForKey:(NSString *)key { return [controller _valueForKey:key]; }
- (void)setValue:(id)value forKey:(NSString *)key { [controller _setValue:value forKey:key]; }
- (id)valueForUndefinedKey:(NSString *)key { return [controller _valueForKey:key]; }
- (BOOL)_ferryIsKeyValueProxy { return YES; }
@end
