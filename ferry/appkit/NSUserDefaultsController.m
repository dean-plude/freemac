/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSController, NSObjectController and NSUserDefaultsController, as
 * Apple's public documentation describes them. No Apple code was used.
 *
 * An object controller holds one content object; its "selection" is a
 * proxy that reads and writes the content's keys (selection.name), or
 * answers NSNoSelectionMarker while there is no content. Observers of
 * selection.someKey hear of the content's changes, and of a new content.
 *
 * The defaults controller's "values" proxy reads and writes the user's
 * defaults by key (values.someKey), applied at once by default, or kept
 * until save: (revert: drops them). Observers of values.someKey hear of
 * changes made through the proxy and of changes made to the defaults
 * themselves. Apps subclass it for their preferences (Gas Mask does). A
 * nib's shared defaults controller is the shared one. */
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

/* A proxy that hears of its source's keys: it observes the first key of
 * each key path observed on it, on whatever object that key is read from,
 * and announces those changes as its own. */
@interface AKeyProxy : NSObject {
@public
    NSMutableDictionary *_keys;   /* first key observed on the proxy -> how many times */
    id _watched;              /* what those keys are observed on (retained) */
}
- (id)_source;
- (void)_sourceWillChange;
- (void)_sourceDidChange;
@end

static char proxy_context;

static NSString *first_key(NSString *keyPath)
{
    NSRange dot = [keyPath rangeOfString:@"."];
    return dot.location == NSNotFound ? keyPath : [keyPath substringToIndex:dot.location];
}

@implementation AKeyProxy
- (id)_source { return nil; }
- (void)dealloc
{
    for (NSString *k in _keys)
        [_watched removeObserver:self forKeyPath:k context:&proxy_context];
    [_watched release];
    [_keys release];
    [super dealloc];
}
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options
            context:(void *)context
{
    NSString *k = first_key(keyPath);
    if (!_keys)
        _keys = [[NSMutableDictionary alloc] init];
    NSUInteger n = [[_keys objectForKey:k] unsignedIntegerValue];
    if (!n) {
        if (!_watched)
            _watched = [[self _source] retain];
        [_watched addObserver:self forKeyPath:k options:NSKeyValueObservingOptionPrior context:&proxy_context];
    }
    [_keys setObject:@(n + 1) forKey:k];
    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}
- (void)_forget:(NSString *)keyPath
{
    NSString *k = first_key(keyPath);
    NSUInteger n = [[_keys objectForKey:k] unsignedIntegerValue];
    if (!n)
        return;
    if (n > 1) {
        [_keys setObject:@(n - 1) forKey:k];
        return;
    }
    [_keys removeObjectForKey:k];
    [_watched removeObserver:self forKeyPath:k context:&proxy_context];
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    [super removeObserver:observer forKeyPath:keyPath];
    [self _forget:keyPath];
}
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    [super removeObserver:observer forKeyPath:keyPath context:context];
    [self _forget:keyPath];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context != &proxy_context) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue])
        [self willChangeValueForKey:keyPath];
    else
        [self didChangeValueForKey:keyPath];
}
/* A new source: the keys are watched on it instead. Wrapped by the owner
 * in will/did of the key the proxy is reached by. */
- (void)_sourceWillChange
{
    for (NSString *k in _keys)
        [_watched removeObserver:self forKeyPath:k context:&proxy_context];
    [_watched release];
    _watched = nil;
}
- (void)_sourceDidChange
{
    _watched = [[self _source] retain];
    for (NSString *k in _keys)
        [_watched addObserver:self forKeyPath:k options:NSKeyValueObservingOptionPrior context:&proxy_context];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return NO; }
@end

/* ---- NSObjectController ------------------------------------------------------------- */

@interface ASelectionProxy : AKeyProxy {
@public
    NSObjectController *controller;   /* not retained: it owns us */
}
@end

@implementation NSObjectController {
    id _content;
    ASelectionProxy *_selection;
    Class _objectClass;
    BOOL _prepares, _editable;
}
- (instancetype)initWithContent:(id)content
{
    if ((self = [super init])) {
        _content = [content retain];
        _objectClass = [NSMutableDictionary class];
        _editable = YES;
        _selection = [[ASelectionProxy alloc] init];
        _selection->controller = self;
    }
    return self;
}
- (instancetype)init { return [self initWithContent:nil]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [self initWithContent:nil]))
        return nil;
    NSString *cls = [coder containsValueForKey:@"NSObjectClassName"] ? [coder decodeObjectForKey:@"NSObjectClassName"] : nil;
    if ([cls isKindOfClass:[NSString class]] && NSClassFromString(cls))
        _objectClass = NSClassFromString(cls);
    if ([coder containsValueForKey:@"NSEditable"])
        _editable = [coder decodeBoolForKey:@"NSEditable"];
    if ([coder containsValueForKey:@"NSAutomaticallyPreparesContent"])
        _prepares = [coder decodeBoolForKey:@"NSAutomaticallyPreparesContent"];
    return self;
}
- (void)awakeFromNib
{
    if (_prepares && !_content)
        [self prepareContent];
}
- (void)dealloc
{
    [_content release];
    if (_selection)
        _selection->controller = nil;
    [_selection release];
    [super dealloc];
}
- (id)content { return _content; }
- (void)setContent:(id)content
{
    if (content == _content)
        return;
    [self willChangeValueForKey:@"selection"];
    [self willChangeValueForKey:@"selectedObjects"];
    [_selection _sourceWillChange];
    [content retain];
    [_content release];
    _content = content;
    [_selection _sourceDidChange];
    [self didChangeValueForKey:@"selectedObjects"];
    [self didChangeValueForKey:@"selection"];
}
- (id)selection { return _selection; }
- (NSArray *)selectedObjects { return _content ? [NSArray arrayWithObject:_content] : [NSArray array]; }
- (Class)objectClass { return _objectClass; }
- (void)setObjectClass:(Class)cls { _objectClass = cls; }
- (BOOL)automaticallyPreparesContent { return _prepares; }
- (void)setAutomaticallyPreparesContent:(BOOL)f { _prepares = f; }
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)canAdd { return _editable && !_content; }
- (BOOL)canRemove { return _editable && _content != nil; }
- (id)newObject { return [[_objectClass alloc] init]; }
- (void)prepareContent
{
    id obj = [self newObject];
    [self setContent:obj];
    [obj release];
}
- (void)addObject:(id)object { [self setContent:object]; }
- (void)removeObject:(id)object
{
    if (object == _content)
        [self setContent:nil];
}
- (void)add:(id)sender
{
    id obj = [self newObject];
    [self addObject:obj];
    [obj release];
}
- (void)remove:(id)sender { [self removeObject:_content]; }
/* bound to contentObject: the bound value is the content */
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentObjectBinding])
        [self setContent:NSIsControllerMarker(value) ? nil : value];
    else
        [super _ferrySetValue:value forBinding:binding];
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentObjectBinding])
        return _content;
    return [super _ferryValueForBinding:binding];
}
@end

@implementation ASelectionProxy
- (id)_source { return [controller content]; }
- (id)valueForKey:(NSString *)key
{
    id c = [controller content];
    return c ? [c valueForKey:key] : NSNoSelectionMarker;
}
- (id)valueForKeyPath:(NSString *)keyPath
{
    id c = [controller content];
    return c ? [c valueForKeyPath:keyPath] : NSNoSelectionMarker;
}
- (void)setValue:(id)value forKey:(NSString *)key { [[controller content] setValue:value forKey:key]; }
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath
{
    [[controller content] setValue:value forKeyPath:keyPath];
}
- (BOOL)_ferryIsKeyValueProxy { return YES; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<selection of %@>", [controller content] ?: @"nothing"];
}
@end

/* ---- NSUserDefaultsController ------------------------------------------------------- */

/* The values proxy: each key is a default. */
@interface AUserDefaultsValues : AKeyProxy {
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
static NSUserDefaultsController *shared;
+ (NSUserDefaultsController *)sharedUserDefaultsController
{
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
    /* "Shared User Defaults Controller" in a nib is the shared one */
    if ([coder containsValueForKey:@"NSSharedInstance"] && [coder decodeBoolForKey:@"NSSharedInstance"] &&
        [self class] == [NSUserDefaultsController class]) {
        [self release];
        return [[NSUserDefaultsController sharedUserDefaultsController] retain];
    }
    self = [self initWithDefaults:nil initialValues:nil];
    if ([coder containsValueForKey:@"NSAppliesImmediately"])
        _appliesImmediately = [coder decodeBoolForKey:@"NSAppliesImmediately"];
    return self;
}
- (void)dealloc
{
    if (_values)
        _values->controller = nil;
    [_values release];
    [_defaults release];
    [_initialValues release];
    [_pending release];
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
    if (_appliesImmediately) {
        /* the defaults announce it, and the proxy passes that on */
        if (value)
            [_defaults setObject:value forKey:key];
        else
            [_defaults removeObjectForKey:key];
        return;
    }
    [_values willChangeValueForKey:key];
    [_pending setObject:value ?: [NSNull null] forKey:key];
    [_values didChangeValueForKey:key];
}
- (void)save:(id)sender
{
    NSDictionary *pending = [[_pending copy] autorelease];
    [_pending removeAllObjects];
    for (NSString *key in pending) {
        id v = [pending objectForKey:key];
        if (v == [NSNull null])
            [_defaults removeObjectForKey:key];
        else
            [_defaults setObject:v forKey:key];
    }
}
/* Each key whose shown value changes is announced around the change. */
- (void)_changeKeys:(NSArray *)keys by:(void (^)(void))change
{
    for (NSString *key in keys)
        [_values willChangeValueForKey:key];
    change();
    for (NSString *key in [keys reverseObjectEnumerator])
        [_values didChangeValueForKey:key];
}
- (void)revert:(id)sender
{
    [self _changeKeys:[_pending allKeys] by:^{ [_pending removeAllObjects]; }];
}
- (void)revertToInitialValues:(id)sender
{
    NSMutableSet *keys = [NSMutableSet setWithArray:[_initialValues allKeys]];
    [keys addObjectsFromArray:[_pending allKeys]];
    [self _changeKeys:[keys allObjects] by:^{
        [_pending removeAllObjects];
        for (NSString *key in _initialValues)
            [_pending setObject:[_initialValues objectForKey:key] forKey:key];
    }];
    if (_appliesImmediately)
        [self save:sender];
}
@end

@implementation AUserDefaultsValues
- (id)_source { return [controller defaults]; }
- (id)valueForKey:(NSString *)key { return [controller _valueForKey:key]; }
- (void)setValue:(id)value forKey:(NSString *)key { [controller _setValue:value forKey:key]; }
- (id)valueForUndefinedKey:(NSString *)key { return [controller _valueForKey:key]; }
- (BOOL)_ferryIsKeyValueProxy { return YES; }
@end
