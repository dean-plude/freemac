/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Cocoa bindings, the first step. A binding ties a property
 * of one object (a control's value, say) to a key path of another (a
 * controller, or the user's defaults). Ferry records each binding, sets the
 * bound property from the key path's value when the binding is made, and
 * sets it again whenever the observed object announces a change of that key
 * path (key-value observing, in Ferry's Foundation). Changes made in the
 * control aren't written back to the key path yet.
 *
 * Written from Apple's public documentation of NSKeyValueBindingCreation;
 * no Apple code was used. */
#import "AInternal.h"

NSString *const NSObservedObjectKey = @"NSObservedObject";
NSString *const NSObservedKeyPathKey = @"NSObservedKeyPath";
NSString *const NSOptionsKey = @"NSOptions";
NSString *const NSValueBinding = @"value";
NSString *const NSEnabledBinding = @"enabled";
NSString *const NSHiddenBinding = @"hidden";
NSString *const NSTitleBinding = @"title";
NSString *const NSContentBinding = @"content";
NSString *const NSSelectedIndexBinding = @"selectedIndex";
NSString *const NSToolTipBinding = @"toolTip";

static char bindings_key;
static NSMutableDictionary *exposed; /* class name -> bindings */

/* Sets the bound property from the key path's value now. */
static void apply_binding(id target, NSString *binding, id observable, NSString *keyPath)
{
    id value = observable;
    for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
        if ([value isKindOfClass:[NSDictionary class]])
            value = [value objectForKey:key];
        else if ([value respondsToSelector:@selector(_ferryIsKeyValueProxy)])
            value = [value valueForKey:key];
        else if ([value respondsToSelector:NSSelectorFromString(key)])
            value = [value valueForKey:key];
        else
            return; /* a key the observed object doesn't have: leave the property as it is */
    }
    if ([binding isEqualToString:NSValueBinding] && [target respondsToSelector:@selector(setObjectValue:)]) {
        [(NSControl *)target setObjectValue:value];
        return;
    }
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[binding substringToIndex:1] uppercaseString],
                                                  [binding substringFromIndex:1]];
    if ([target respondsToSelector:NSSelectorFromString(setter)])
        [target setValue:value forKey:binding];
}

/* Watches one binding's key path and sets the property again on a change.
 * It holds neither object, as a Mac's bindings hold neither strongly. */
@interface ABindingObserver : NSObject {
@public
    id target, observed;
    NSString *binding, *keyPath;
    BOOL observing;
}
- (void)stop;
@end
@implementation ABindingObserver
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    apply_binding(target, binding, observed, keyPath);
}
- (void)stop
{
    if (observing)
        [observed removeObserver:self forKeyPath:keyPath];
    observing = NO;
}
- (void)dealloc
{
    [self stop];
    [binding release];
    [keyPath release];
    [super dealloc];
}
@end

@implementation NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)binding
{
    if (!binding)
        return;
    if (!exposed)
        exposed = [[NSMutableDictionary alloc] init];
    NSString *name = NSStringFromClass(self);
    NSMutableArray *list = [exposed objectForKey:name];
    if (!list) {
        list = [NSMutableArray array];
        [exposed setObject:list forKey:name];
    }
    if (![list containsObject:binding])
        [list addObject:binding];
}
- (NSArray *)exposedBindings
{
    NSMutableArray *all = [NSMutableArray array];
    for (Class c = [self class]; c; c = class_getSuperclass(c))
        for (NSString *b in [exposed objectForKey:NSStringFromClass(c)])
            if (![all containsObject:b])
                [all addObject:b];
    return all;
}
- (Class)valueClassForBinding:(NSString *)binding { return Nil; }

- (void)bind:(NSString *)binding toObject:(id)observable withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options
{
    if (!binding || !keyPath)
        return;
    NSMutableDictionary *all = objc_getAssociatedObject(self, &bindings_key);
    if (!all) {
        all = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &bindings_key, all, OBJC_ASSOCIATION_RETAIN);
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (observable)
        [info setObject:observable forKey:NSObservedObjectKey];
    [info setObject:keyPath forKey:NSObservedKeyPathKey];
    [info setObject:options ?: [NSDictionary dictionary] forKey:NSOptionsKey];
    [all setObject:info forKey:binding];
    if (!observable)
        return;
    ABindingObserver *o = [[[ABindingObserver alloc] init] autorelease];
    o->target = self;
    o->binding = [binding copy];
    o->observed = observable;
    o->keyPath = [keyPath copy];
    [info setObject:o forKey:@"ferryObserver"];
    [observable addObserver:o forKeyPath:keyPath options:0 context:NULL];
    o->observing = YES;
    apply_binding(self, binding, observable, keyPath);
}
- (void)unbind:(NSString *)binding
{
    NSMutableDictionary *all = objc_getAssociatedObject(self, &bindings_key);
    [(ABindingObserver *)[[all objectForKey:binding] objectForKey:@"ferryObserver"] stop];
    [all removeObjectForKey:binding];
}
- (NSDictionary *)infoForBinding:(NSString *)binding
{
    return [objc_getAssociatedObject(self, &bindings_key) objectForKey:binding];
}
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding { return [NSArray array]; }
@end
