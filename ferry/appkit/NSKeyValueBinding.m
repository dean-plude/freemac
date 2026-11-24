/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Cocoa bindings. A binding ties a property of a view (a
 * control's value, say) to a key path of another object (a controller, or
 * the user's defaults). The bound property is set from the key path's
 * value when the binding is made and again whenever the observed object
 * announces a change of it (key-value observing, in Ferry's Foundation);
 * what the user changes in a control (a click, a choice, an edit ended) is
 * written back to the key path with setValue:forKeyPath:.
 *
 * The options: a value transformer, by name or as an object, turns the
 * key path's value into the view's (and back, if it can, for a write);
 * NSNullPlaceholderBindingOption stands in for nil (a text field shows it
 * greyed, as its placeholder); the no-selection, multiple-values and
 * not-applicable placeholders stand in for a controller's markers;
 * NSContinuouslyUpdatesValueBindingOption writes a text field's value back
 * as it is typed, not when the editing ends. Several enabled bindings
 * (enabled, enabled2, ...) are combined with AND, hidden ones with OR.
 * Pop-up buttons take content, contentObjects and contentValues for their
 * items and selectedIndex, selectedObject, selectedValue and selectedTag
 * for the choice. A key the observed object doesn't have leaves the
 * property as it is, unless NSRaisesForNotApplicableKeysBindingOption is
 * YES.
 *
 * Written from Apple's public documentation of NSKeyValueBindingCreation
 * and the Cocoa Bindings Reference; no Apple code was used. */
#import "AInternal.h"

NSString *const NSObservedObjectKey = @"NSObservedObject";
NSString *const NSObservedKeyPathKey = @"NSObservedKeyPath";
NSString *const NSOptionsKey = @"NSOptions";

NSString *const NSValueBinding = @"value";
NSString *const NSEnabledBinding = @"enabled";
NSString *const NSHiddenBinding = @"hidden";
NSString *const NSTitleBinding = @"title";
NSString *const NSAlternateTitleBinding = @"alternateTitle";
NSString *const NSContentBinding = @"content";
NSString *const NSContentValuesBinding = @"contentValues";
NSString *const NSContentObjectsBinding = @"contentObjects";
NSString *const NSContentObjectBinding = @"contentObject";
NSString *const NSSelectedIndexBinding = @"selectedIndex";
NSString *const NSSelectedObjectBinding = @"selectedObject";
NSString *const NSSelectedValueBinding = @"selectedValue";
NSString *const NSSelectedTagBinding = @"selectedTag";
NSString *const NSToolTipBinding = @"toolTip";
NSString *const NSEditableBinding = @"editable";
NSString *const NSMinValueBinding = @"minValue";
NSString *const NSMaxValueBinding = @"maxValue";
NSString *const NSTextColorBinding = @"textColor";
NSString *const NSImageBinding = @"image";
NSString *const NSFontBinding = @"font";

NSString *const NSNullPlaceholderBindingOption = @"NSNullPlaceholder";
NSString *const NSNoSelectionPlaceholderBindingOption = @"NSNoSelectionPlaceholder";
NSString *const NSMultipleValuesPlaceholderBindingOption = @"NSMultipleValuesPlaceholder";
NSString *const NSNotApplicablePlaceholderBindingOption = @"NSNotApplicablePlaceholder";
NSString *const NSValueTransformerNameBindingOption = @"NSValueTransformerName";
NSString *const NSValueTransformerBindingOption = @"NSValueTransformer";
NSString *const NSContinuouslyUpdatesValueBindingOption = @"NSContinuouslyUpdatesValue";
NSString *const NSRaisesForNotApplicableKeysBindingOption = @"NSRaisesForNotApplicableKeys";
NSString *const NSConditionallySetsEnabledBindingOption = @"NSConditionallySetsEnabled";
NSString *const NSConditionallySetsEditableBindingOption = @"NSConditionallySetsEditable";
NSString *const NSAllowsEditingMultipleValuesSelectionBindingOption = @"NSAllowsEditingMultipleValuesSelection";
NSString *const NSValidatesImmediatelyBindingOption = @"NSValidatesImmediately";

/* ---- the markers a controller's selection answers ---- */

@interface ABindingMarker : NSObject <NSCopying> {
    const char *_name;
}
@end

id NSMultipleValuesMarker, NSNoSelectionMarker, NSNotApplicableMarker;

@implementation ABindingMarker
+ (void)load
{
    ABindingMarker *m;
    m = [[ABindingMarker alloc] init], m->_name = "NSMultipleValuesMarker", NSMultipleValuesMarker = m;
    m = [[ABindingMarker alloc] init], m->_name = "NSNoSelectionMarker", NSNoSelectionMarker = m;
    m = [[ABindingMarker alloc] init], m->_name = "NSNotApplicableMarker", NSNotApplicableMarker = m;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"<%s>", _name]; }
/* a key path through a marker stays the marker */
- (id)valueForKey:(NSString *)key { return self; }
- (id)valueForKeyPath:(NSString *)keyPath { return self; }
@end

BOOL NSIsControllerMarker(id object)
{
    return object && (object == NSMultipleValuesMarker || object == NSNoSelectionMarker ||
                      object == NSNotApplicableMarker);
}

/* ---- one binding ---- */

@interface ABinding : NSObject {
@public
    id view;                 /* not retained: it owns us */
    NSString *name;
    id observed;             /* retained, as the binding's info holds it */
    NSString *keyPath;
    NSDictionary *options;
    NSDictionary *info;
    BOOL observing, pushing, placeholderShown;
    NSString *savedPlaceholder;   /* a text field's own, while a binding's shows */
}
- (void)stop;
@end

static char bindings_key;

static NSMutableDictionary *bindings_of(id view, BOOL create)
{
    NSMutableDictionary *all = objc_getAssociatedObject(view, &bindings_key);
    if (!all && create) {
        all = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(view, &bindings_key, all, OBJC_ASSOCIATION_RETAIN);
    }
    return all;
}

static id option(ABinding *b, NSString *key)
{
    id v = [b->options objectForKey:key];
    return v == [NSNull null] ? nil : v;
}

static NSValueTransformer *transformer_of(ABinding *b)
{
    id t = option(b, NSValueTransformerBindingOption);
    if ([t isKindOfClass:[NSValueTransformer class]])
        return t;
    NSString *n = option(b, NSValueTransformerNameBindingOption);
    return [n isKindOfClass:[NSString class]] && [n length] ? [NSValueTransformer valueTransformerForName:n] : nil;
}

/* "enabled2" is an enabled binding, "hidden3" a hidden one. */
static NSString *base_name(NSString *name)
{
    NSUInteger n = [name length];
    while (n > 1 && [name characterAtIndex:n - 1] >= '0' && [name characterAtIndex:n - 1] <= '9')
        n--;
    return n == [name length] ? name : [name substringToIndex:n];
}

/* The key path's value; the not-applicable marker for a key the object
 * doesn't have (unless the binding asks for the exception). */
static id model_value(ABinding *b)
{
    @try {
        return [b->observed valueForKeyPath:b->keyPath];
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException] ||
            [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
            @throw;
        return NSNotApplicableMarker;
    }
}

static BOOL is_text_value(ABinding *b)
{
    return [b->view isKindOfClass:[NSTextField class]] && [b->name isEqualToString:NSValueBinding];
}

/* What the view is given for the key path's value v. *keep: leave the view
 * as it is; *placeholder: a text field shows this greyed instead. */
static id shown_value(ABinding *b, id v, BOOL *keep, NSString **placeholder)
{
    *keep = NO;
    *placeholder = nil;
    if (NSIsControllerMarker(v)) {
        NSString *key = v == NSNoSelectionMarker        ? NSNoSelectionPlaceholderBindingOption
                        : v == NSMultipleValuesMarker ? NSMultipleValuesPlaceholderBindingOption
                                                      : NSNotApplicablePlaceholderBindingOption;
        id p = option(b, key);
        if (!p && v == NSNotApplicableMarker) {
            *keep = YES;
            return nil;
        }
        if (is_text_value(b)) {
            *placeholder = p ?: (v == NSNoSelectionMarker ? @"No Selection" : @"Multiple Values");
            return nil;
        }
        return p;
    }
    NSValueTransformer *t = transformer_of(b);
    if (t)
        v = [t transformedValue:v];
    if (v == [NSNull null])
        v = nil;
    if (!v) {
        id p = option(b, NSNullPlaceholderBindingOption);
        if (p && is_text_value(b))
            *placeholder = [p description];
        else
            v = p;
    }
    return v;
}

static BOOL truth(id v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : v != nil; }

/* enabled, enabled2, ... together: all must be true. hidden ones: any. */
static void apply_combined(id view, NSString *base)
{
    BOOL hidden = [base isEqualToString:NSHiddenBinding], result = !hidden;
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all) {
        ABinding *b = [all objectForKey:name];
        if (![base_name(name) isEqualToString:base] || !b->observed)
            continue;
        BOOL keep;
        NSString *placeholder;
        id v = shown_value(b, model_value(b), &keep, &placeholder);
        if (keep)
            continue;
        if (hidden)
            result = result || truth(v);
        else
            result = result && truth(v);
    }
    if (hidden && [view respondsToSelector:@selector(setHidden:)])
        [(NSView *)view setHidden:result];
    else if (!hidden && [view respondsToSelector:@selector(setEnabled:)])
        [(NSControl *)view setEnabled:result];
}

static void apply(ABinding *b)
{
    if (!b->observed)
        return;
    NSString *base = base_name(b->name);
    if ([base isEqualToString:NSEnabledBinding] || [base isEqualToString:NSHiddenBinding]) {
        apply_combined(b->view, base);
        return;
    }
    BOOL keep;
    NSString *placeholder;
    id v = shown_value(b, model_value(b), &keep, &placeholder);
    if (keep)
        return;
    if (is_text_value(b)) {
        NSTextField *f = b->view;
        if (placeholder) {
            if (!b->placeholderShown) {
                b->savedPlaceholder = [[f placeholderString] copy];
                b->placeholderShown = YES;
            }
            [f setPlaceholderString:placeholder];
        } else if (b->placeholderShown) {
            [f setPlaceholderString:b->savedPlaceholder];
            [b->savedPlaceholder release];
            b->savedPlaceholder = nil;
            b->placeholderShown = NO;
        }
    }
    [b->view _ferrySetValue:v forBinding:b->name];
}

/* Writes what the view now shows back to the key path. */
static void push(ABinding *b)
{
    id v = [b->view _ferryValueForBinding:b->name];
    if (is_text_value(b) && option(b, NSNullPlaceholderBindingOption) && [v isKindOfClass:[NSString class]] &&
        ![v length])
        v = nil;   /* an emptied field stands for nil, as its placeholder shows */
    NSValueTransformer *t = transformer_of(b);
    if (t) {
        if (![[t class] allowsReverseTransformation])
            return;
        v = [t reverseTransformedValue:v];
    }
    id now = model_value(b);
    if (now == NSNotApplicableMarker || now == v || [now isEqual:v])
        return;
    b->pushing = YES;
    @try {
        [b->observed setValue:v forKeyPath:b->keyPath];
    } @finally {
        b->pushing = NO;
    }
    /* shown again as the model now has it (a placeholder for nil, say),
     * unless the text is still being typed */
    if (![b->view isKindOfClass:[NSTextField class]] || ![(NSTextField *)b->view _isEditing])
        apply(b);
}

static BOOL writable(NSString *name)
{
    return [name isEqualToString:NSValueBinding] || [name isEqualToString:NSSelectedIndexBinding] ||
           [name isEqualToString:NSSelectedObjectBinding] || [name isEqualToString:NSSelectedValueBinding] ||
           [name isEqualToString:NSSelectedTagBinding];
}

void ABindingsPush(id view, BOOL continuousOnly)
{
    NSDictionary *all = bindings_of(view, NO);
    if (![all count])
        return;
    [[view retain] autorelease];
    for (NSString *name in [[all allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        ABinding *b = [all objectForKey:name];
        if (!b || !b->observed || !writable(name))
            continue;
        if (continuousOnly && ![option(b, NSContinuouslyUpdatesValueBindingOption) boolValue])
            continue;
        push(b);
    }
}

BOOL ABindingsWantContinuous(id view)
{
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all)
        if ([option([all objectForKey:name], NSContinuouslyUpdatesValueBindingOption) boolValue])
            return YES;
    return NO;
}

@implementation ABinding
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (pushing)
        return;   /* the view already shows it */
    [[self retain] autorelease];
    apply(self);
    /* a pop-up's items changed: its choice is set again from its bindings */
    if ([view isKindOfClass:[NSPopUpButton class]] &&
        ([name isEqualToString:NSContentBinding] || [name isEqualToString:NSContentObjectsBinding] ||
         [name isEqualToString:NSContentValuesBinding])) {
        NSDictionary *all = bindings_of(view, NO);
        for (NSString *n in @[ NSSelectedIndexBinding, NSSelectedObjectBinding, NSSelectedValueBinding,
                               NSSelectedTagBinding ])
            if ([all objectForKey:n])
                apply([all objectForKey:n]);
    }
}
- (void)stop
{
    if (observing)
        [observed removeObserver:self forKeyPath:keyPath];
    observing = NO;
    if (placeholderShown && [view isKindOfClass:[NSTextField class]])
        [(NSTextField *)view setPlaceholderString:savedPlaceholder];
    placeholderShown = NO;
}
- (void)dealloc
{
    [self stop];
    [name release];
    [observed release];
    [keyPath release];
    [options release];
    [info release];
    [savedPlaceholder release];
    [super dealloc];
}
@end

/* ---- what each kind of view binds ---- */

static NSMutableDictionary *exposed; /* class name -> bindings */

static void expose(NSString *cls, NSArray *names)
{
    NSMutableArray *list = [exposed objectForKey:cls];
    if (!list) {
        list = [NSMutableArray array];
        [exposed setObject:list forKey:cls];
    }
    for (NSString *n in names)
        if (![list containsObject:n])
            [list addObject:n];
}

/* The bindings Apple's Cocoa Bindings Reference lists for Ferry's views
 * and controllers. */
static void expose_defaults(void)
{
    if (exposed)
        return;
    exposed = [[NSMutableDictionary alloc] init];
    expose(@"NSView", @[ NSHiddenBinding, NSToolTipBinding ]);
    expose(@"NSControl", @[ NSEnabledBinding ]);
    expose(@"NSTextField", @[ NSValueBinding, NSEditableBinding, NSTextColorBinding, NSFontBinding ]);
    expose(@"NSButton", @[ NSValueBinding, NSTitleBinding, NSAlternateTitleBinding, NSImageBinding ]);
    expose(@"NSPopUpButton", @[ NSContentBinding, NSContentObjectsBinding, NSContentValuesBinding,
                                NSSelectedIndexBinding, NSSelectedObjectBinding, NSSelectedTagBinding,
                                NSSelectedValueBinding ]);
    expose(@"NSSlider", @[ NSValueBinding, NSMinValueBinding, NSMaxValueBinding ]);
    expose(@"NSObjectController", @[ NSContentObjectBinding, NSEditableBinding ]);
}

@implementation NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)binding
{
    if (!binding)
        return;
    expose_defaults();
    expose(NSStringFromClass(self), @[ binding ]);
}
- (NSArray *)exposedBindings
{
    expose_defaults();
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
    [self unbind:binding];
    ABinding *b = [[[ABinding alloc] init] autorelease];
    b->view = self;
    b->name = [binding copy];
    b->observed = [observable retain];
    b->keyPath = [keyPath copy];
    b->options = [(options ?: [NSDictionary dictionary]) copy];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (observable)
        [info setObject:observable forKey:NSObservedObjectKey];
    [info setObject:keyPath forKey:NSObservedKeyPathKey];
    [info setObject:b->options forKey:NSOptionsKey];
    b->info = [info copy];
    [bindings_of(self, YES) setObject:b forKey:binding];
    if (!observable)
        return;
    @try {
        [observable addObserver:b forKeyPath:keyPath options:0 context:NULL];
        b->observing = YES;
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException] ||
            [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
            @throw;
    }
    apply(b);
}
- (void)unbind:(NSString *)binding
{
    NSMutableDictionary *all = bindings_of(self, NO);
    ABinding *b = [all objectForKey:binding];
    if (!b)
        return;
    [b stop];
    [all removeObjectForKey:binding];
}
- (NSDictionary *)infoForBinding:(NSString *)binding
{
    ABinding *b = [bindings_of(self, NO) objectForKey:binding];
    return b ? b->info : nil;
}
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding { return [NSArray array]; }
@end

/* How a binding sets and reads the view's property: its value is the
 * objectValue of a control, anything else the property of that name. */
@implementation NSObject (FerryBindings)
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding] && [self respondsToSelector:@selector(setObjectValue:)]) {
        [(NSControl *)self setObjectValue:value];
        return;
    }
    NSString *key = base_name(binding);
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString],
                                                  [key substringFromIndex:1]];
    if (![self respondsToSelector:NSSelectorFromString(setter)])
        return;
    @try {
        [self setValue:value forKey:key];
    } @catch (NSException *e) {
        /* nil for a number, say: the property is left as it is */
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding] && [self respondsToSelector:@selector(objectValue)])
        return [(NSControl *)self objectValue];
    @try {
        return [self valueForKey:base_name(binding)];
    } @catch (NSException *e) {
        return nil;
    }
}
@end

/* A pop-up's items come from its content bindings; its choice from the
 * selection ones. */
@implementation NSPopUpButton (FerryBindings)
- (id)_ferryBoundValue:(NSString *)binding
{
    ABinding *b = [bindings_of(self, NO) objectForKey:binding];
    if (!b || !b->observed)
        return nil;
    BOOL keep;
    NSString *placeholder;
    id v = shown_value(b, model_value(b), &keep, &placeholder);
    if ([v isKindOfClass:[NSSet class]])
        v = [v allObjects];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}
- (void)_ferryRebuildItems
{
    NSArray *content = [self _ferryBoundValue:NSContentBinding];
    NSArray *objects = [self _ferryBoundValue:NSContentObjectsBinding] ?: content;
    NSArray *titles = [self _ferryBoundValue:NSContentValuesBinding];
    NSUInteger n = MAX([objects count], [titles count]);
    if (!titles && !objects)
        return;
    [self removeAllItems];
    NSMenu *menu = [self menu];
    for (NSUInteger i = 0; i < n; i++) {
        id obj = i < [objects count] ? [objects objectAtIndex:i] : nil;
        id title = i < [titles count] ? [titles objectAtIndex:i] : obj;
        NSString *s = title == [NSNull null] || !title ? @"" : [title description];
        NSMenuItem *item = [menu addItemWithTitle:s action:NULL keyEquivalent:@""];
        [item setRepresentedObject:obj == [NSNull null] ? nil : obj];
    }
    if ([self numberOfItems])
        [self selectItemAtIndex:0];
}
- (void)_ferrySelectIndex:(NSInteger)i
{
    if (i >= 0 && i < [self numberOfItems])
        [self selectItemAtIndex:i];
    else
        [self selectItem:nil];
}
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentBinding] || [binding isEqualToString:NSContentObjectsBinding] ||
        [binding isEqualToString:NSContentValuesBinding]) {
        [self _ferryRebuildItems];
    } else if ([binding isEqualToString:NSSelectedIndexBinding]) {
        [self _ferrySelectIndex:value ? [value integerValue] : -1];
    } else if ([binding isEqualToString:NSSelectedObjectBinding]) {
        NSInteger found = -1;
        for (NSInteger i = 0; i < [self numberOfItems] && value; i++) {
            id obj = [[self itemAtIndex:i] representedObject];
            if (obj == value || [obj isEqual:value]) {
                found = i;
                break;
            }
        }
        [self _ferrySelectIndex:found];
    } else if ([binding isEqualToString:NSSelectedValueBinding]) {
        [self _ferrySelectIndex:value ? [self indexOfItemWithTitle:[value description]] : -1];
    } else if ([binding isEqualToString:NSSelectedTagBinding]) {
        [self _ferrySelectIndex:value ? [self indexOfItemWithTag:[value integerValue]] : -1];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
    [self setNeedsDisplay:YES];
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSSelectedIndexBinding])
        return @([self indexOfSelectedItem]);
    if ([binding isEqualToString:NSSelectedObjectBinding])
        return [[self selectedItem] representedObject];
    if ([binding isEqualToString:NSSelectedValueBinding])
        return [self selectedItem] ? [self titleOfSelectedItem] : nil;
    if ([binding isEqualToString:NSSelectedTagBinding])
        return [self selectedItem] ? @([self selectedTag]) : nil;
    return [super _ferryValueForBinding:binding];
}
@end
