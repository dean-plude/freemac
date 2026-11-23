/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Cocoa bindings, the first step. A binding ties a property
 * of one object (a control's value, say) to a key path of another (a
 * controller, or the user's defaults). Ferry records each binding and sets
 * the bound property once, from the key path's value when the binding is
 * made; it doesn't follow later changes in either direction yet, because
 * Ferry's Foundation has no key-value observing.
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
    AWarnOnce("Cocoa bindings that follow changes (each bound value is set once)");
    if (!observable)
        return;
    id value = observable;
    for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
        if ([value isKindOfClass:[NSDictionary class]])
            value = [value objectForKey:key];
        else if ([value respondsToSelector:NSSelectorFromString(key)])
            value = [value valueForKey:key];
        else
            return; /* a key the observed object doesn't have: leave the property as it is */
    }
    if ([binding isEqualToString:NSValueBinding] && [self respondsToSelector:@selector(setObjectValue:)]) {
        [(NSControl *)self setObjectValue:value];
        return;
    }
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[binding substringToIndex:1] uppercaseString],
                                                  [binding substringFromIndex:1]];
    if ([self respondsToSelector:NSSelectorFromString(setter)])
        [self setValue:value forKey:binding];
}
- (void)unbind:(NSString *)binding
{
    [objc_getAssociatedObject(self, &bindings_key) removeObjectForKey:binding];
}
- (NSDictionary *)infoForBinding:(NSString *)binding
{
    return [objc_getAssociatedObject(self, &bindings_key) objectForKey:binding];
}
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding { return [NSArray array]; }
@end
