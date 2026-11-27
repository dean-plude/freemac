/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSDictionaryController (Ferry 0.19.0), as Apple's public documentation
 * describes it. No Apple code was used.
 *
 * Its content is a dictionary, given with setContent: or by the
 * contentDictionary binding; it shows it as an array controller of
 * key-value pairs (arrangedObjects.key, arrangedObjects.value and
 * arrangedObjects.localizedKey), one for each key of the dictionary and of
 * includedKeys, less excludedKeys, in the order of their keys. Setting a
 * pair's value or key changes the dictionary (a renamed key keeps its
 * value); adding a pair (newObject makes one with initialKey and
 * initialValue, the key made unique with a number: "key", "key1",
 * "key2"...) puts its key in, and removing one takes its key out. The
 * changed dictionary is written back to the bound key path as a new
 * dictionary, or changed in place when the content is a mutable dictionary
 * that isn't bound. A pair's localizedKey comes from
 * localizedKeyDictionary, else from localizedKeyTable in the main bundle,
 * else is the key. The pairs are kept from one change of the dictionary
 * to the next, so the selection stays on them. */
#import "AInternal.h"

NSString *const NSContentDictionaryBinding = @"contentDictionary";
NSString *const NSIncludedKeysBinding = @"includedKeys";
NSString *const NSExcludedKeysBinding = @"excludedKeys";
NSString *const NSInitialKeyBinding = @"initialKey";
NSString *const NSInitialValueBinding = @"initialValue";
NSString *const NSLocalizedKeyDictionaryBinding = @"localizedKeyDictionary";

@interface NSDictionaryController (FerryPairs)
- (void)_pair:(id)pair renamedFrom:(NSString *)old;
- (void)_pairValueChanged:(id)pair;
- (NSString *)_localizedKeyFor:(NSString *)key;
- (BOOL)_includes:(NSString *)key;
@end

@interface ADictionaryPair : NSObject <NSDictionaryControllerKeyValuePair> {
@public
    NSDictionaryController *controller;   /* not retained: it holds us */
    NSString *_key;
    id _value;
}
@end

@implementation ADictionaryPair
@synthesize key = _key, value = _value;
- (void)dealloc
{
    [_key release];
    [_value release];
    [super dealloc];
}
- (void)setKey:(NSString *)key
{
    if (key == _key || [key isEqual:_key])
        return;
    NSString *old = [_key autorelease];
    _key = [key copy];
    [controller _pair:self renamedFrom:old];
}
- (void)setValue:(id)value
{
    if (value == _value)
        return;
    [_value autorelease];
    _value = [value retain];
    [controller _pairValueChanged:self];
}
- (NSString *)localizedKey { return controller ? [controller _localizedKeyFor:_key] : _key; }
- (BOOL)isExplicitlyIncluded { return controller && [controller _includes:_key]; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ = %@", _key, _value]; }
@end

@implementation NSDictionaryController {
    NSDictionary *_dict;
    NSString *_initialKey;
    id _initialValue;
    NSArray *_included, *_excluded;
    NSDictionary *_localized;
    NSString *_localizedTable;
    BOOL _writing, _changingPairs;
}

- (instancetype)initWithContent:(id)content
{
    if ((self = [super initWithContent:nil])) {
        _initialKey = @"key";
        _initialValue = @"value";
        if (content)
            [self setContent:content];
    }
    return self;
}
/* From a nib (Ferry 0.20.0): the initial key and value, the included and
 * excluded keys and the localized key dictionary and table. The key names
 * are a guess at Interface Builder's, after its attributes' names. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    id v;
#define DECODED(key, cls) ([coder containsValueForKey:key] && [(v = [coder decodeObjectForKey:key]) isKindOfClass:[cls class]])
    if (DECODED(@"NSInitialKey", NSString))
        [self setInitialKey:v];
    if ([coder containsValueForKey:@"NSInitialValue"])
        [self setInitialValue:[coder decodeObjectForKey:@"NSInitialValue"]];
    if (DECODED(@"NSIncludedKeys", NSArray))
        [self setIncludedKeys:v];
    if (DECODED(@"NSExcludedKeys", NSArray))
        [self setExcludedKeys:v];
    if (DECODED(@"NSLocalizedKeyDictionary", NSDictionary))
        [self setLocalizedKeyDictionary:v];
    if (DECODED(@"NSLocalizedKeyTable", NSString))
        [self setLocalizedKeyTable:v];
#undef DECODED
    return self;
}
- (void)dealloc
{
    for (ADictionaryPair *p in [self _contentObjects])
        if ([p isKindOfClass:[ADictionaryPair class]] && p->controller == self)
            p->controller = nil;
    [_dict release];
    [_initialKey release];
    [_initialValue release];
    [_included release];
    [_excluded release];
    [_localized release];
    [_localizedTable release];
    [super dealloc];
}

/* ---- the content: a dictionary, shown as pairs ---- */

- (id)content { return _dict; }
- (void)prepareContent { [self setContent:[NSMutableDictionary dictionary]]; }
- (void)setContent:(id)content
{
    if (NSIsControllerMarker(content) || ![content isKindOfClass:[NSDictionary class]])
        content = nil;
    [content retain];
    [_dict release];
    _dict = content;
    [self _rebuildPairs];
}
- (BOOL)_includes:(NSString *)key { return key && [_included containsObject:key]; }
- (NSString *)_localizedKeyFor:(NSString *)key
{
    NSString *l = key ? [_localized objectForKey:key] : nil;
    if (l)
        return l;
    if (key && _localizedTable)
        return [[NSBundle mainBundle] localizedStringForKey:key value:key table:_localizedTable];
    return key;
}
/* The pairs for the dictionary's keys and the included ones, less the
 * excluded, reusing the pairs already shown. */
- (void)_rebuildPairs
{
    NSMutableArray *keys = [NSMutableArray array];
    for (id k in [_dict allKeys])
        if ([k isKindOfClass:[NSString class]] && ![keys containsObject:k])
            [keys addObject:k];
    for (NSString *k in _included)
        if (![keys containsObject:k])
            [keys addObject:k];
    [keys removeObjectsInArray:_excluded ?: @[]];
    [keys sortUsingSelector:@selector(compare:)];
    NSMutableDictionary *old = [NSMutableDictionary dictionary];
    for (ADictionaryPair *p in [self _contentObjects])
        if ([p isKindOfClass:[ADictionaryPair class]] && p->_key && ![old objectForKey:p->_key])
            [old setObject:p forKey:p->_key];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in keys) {
        ADictionaryPair *p = [old objectForKey:k];
        if (!p) {
            p = [[[ADictionaryPair alloc] init] autorelease];
            p->_key = [k copy];
        }
        p->controller = self;
        id v = [_dict objectForKey:k];
        if (v != p->_value && ![v isEqual:p->_value]) {
            [p willChangeValueForKey:@"value"];
            [p->_value release];
            p->_value = [v retain];
            [p didChangeValueForKey:@"value"];
        }
        [pairs addObject:p];
    }
    for (ADictionaryPair *p in [old allValues])
        if ([pairs indexOfObjectIdenticalTo:p] == NSNotFound)
            p->controller = nil;
    _changingPairs = YES;
    @try {
        [super setContent:pairs];
    } @finally {
        _changingPairs = NO;
    }
}
/* The dictionary changed: written back to the bound key path, or kept. */
- (void)_writeDictionary:(NSDictionary *)d
{
    NSDictionary *info = [self infoForBinding:NSContentDictionaryBinding];
    if (info) {
        _writing = YES;
        @try {
            [[info objectForKey:NSObservedObjectKey] setValue:[[d copy] autorelease]
                                                   forKeyPath:[info objectForKey:NSObservedKeyPathKey]];
        } @finally {
            _writing = NO;
        }
    }
    if (!info && [_dict isKindOfClass:[NSMutableDictionary class]]) {
        [(NSMutableDictionary *)_dict setDictionary:d];
    } else if (d != _dict) {
        id wasDict = _dict;
        _dict = [d copy];
        [wasDict release];
    }
}
- (NSMutableDictionary *)_editableDictionary
{
    return _dict ? [[_dict mutableCopy] autorelease] : [NSMutableDictionary dictionary];
}
- (void)_pair:(ADictionaryPair *)pair renamedFrom:(NSString *)old
{
    NSMutableDictionary *d = [self _editableDictionary];
    BOOL clash = pair->_key && [d objectForKey:pair->_key] != nil;
    if (old)
        [d removeObjectForKey:old];
    if (pair->_key && pair->_value)
        [d setObject:pair->_value forKey:pair->_key];
    [self _writeDictionary:d];
    if (clash)
        [self _rebuildPairs];   /* two pairs with one key: one is left */
}
- (void)_pairValueChanged:(ADictionaryPair *)pair
{
    if (!pair->_key)
        return;
    NSMutableDictionary *d = [self _editableDictionary];
    if (pair->_value)
        [d setObject:pair->_value forKey:pair->_key];
    else
        [d removeObjectForKey:pair->_key];
    [self _writeDictionary:d];
}

/* Pairs added or removed through the array controller change the
 * dictionary too. */
- (void)_contentInsert:(NSArray *)objects atIndexes:(NSIndexSet *)indexes
{
    [super _contentInsert:objects atIndexes:indexes];
    if (_changingPairs)
        return;
    NSMutableDictionary *d = [self _editableDictionary];
    for (ADictionaryPair *p in objects)
        if ([p isKindOfClass:[ADictionaryPair class]]) {
            p->controller = self;
            if (p->_key && p->_value)
                [d setObject:p->_value forKey:p->_key];
        }
    [self _writeDictionary:d];
}
- (void)_contentRemove:(NSArray *)objects
{
    [super _contentRemove:objects];
    if (_changingPairs)
        return;
    NSMutableDictionary *d = [self _editableDictionary];
    for (ADictionaryPair *p in objects)
        if ([p isKindOfClass:[ADictionaryPair class]]) {
            if (p->_key)
                [d removeObjectForKey:p->_key];
            p->controller = nil;
        }
    [self _writeDictionary:d];
}

/* A new pair: the initial key, made unique, and the initial value. */
- (id)newObject
{
    NSMutableSet *taken = [NSMutableSet setWithArray:[_dict allKeys] ?: @[]];
    for (ADictionaryPair *p in [self _contentObjects])
        if ([p isKindOfClass:[ADictionaryPair class]] && p->_key)
            [taken addObject:p->_key];
    NSString *base = _initialKey ?: @"key", *key = base;
    for (NSUInteger n = 1; [taken containsObject:key]; n++)
        key = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
    ADictionaryPair *p = [[ADictionaryPair alloc] init];
    p->_key = [key copy];
    p->_value = [_initialValue retain];
    p->controller = self;
    return p;
}

/* ---- settings ---- */

- (NSString *)initialKey { return _initialKey; }
- (void)setInitialKey:(NSString *)k
{
    [_initialKey autorelease];
    _initialKey = [k copy];
}
- (id)initialValue { return _initialValue; }
- (void)setInitialValue:(id)v
{
    [_initialValue autorelease];
    _initialValue = [v retain];
}
- (NSArray *)includedKeys { return _included ?: [NSArray array]; }
- (void)setIncludedKeys:(NSArray *)keys
{
    [_included autorelease];
    _included = [keys copy];
    [self _rebuildPairs];
}
- (NSArray *)excludedKeys { return _excluded ?: [NSArray array]; }
- (void)setExcludedKeys:(NSArray *)keys
{
    [_excluded autorelease];
    _excluded = [keys copy];
    [self _rebuildPairs];
}
- (NSDictionary *)localizedKeyDictionary { return _localized ?: [NSDictionary dictionary]; }
- (void)setLocalizedKeyDictionary:(NSDictionary *)d
{
    [_localized autorelease];
    _localized = [d copy];
}
- (NSString *)localizedKeyTable { return _localizedTable; }
- (void)setLocalizedKeyTable:(NSString *)t
{
    [_localizedTable autorelease];
    _localizedTable = [t copy];
}

/* ---- bindings ---- */

- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentDictionaryBinding]) {
        if (_writing) {
            /* our own change: the pairs show it already */
            if (value != _dict) {
                [_dict release];
                _dict = [([value isKindOfClass:[NSDictionary class]] ? value : nil) copy];
            }
        } else {
            [self setContent:value];
        }
    } else if ([binding isEqualToString:NSIncludedKeysBinding]) {
        [self setIncludedKeys:[value isKindOfClass:[NSArray class]] ? value : nil];
    } else if ([binding isEqualToString:NSExcludedKeysBinding]) {
        [self setExcludedKeys:[value isKindOfClass:[NSArray class]] ? value : nil];
    } else if ([binding isEqualToString:NSInitialKeyBinding]) {
        [self setInitialKey:[value isKindOfClass:[NSString class]] ? value : nil];
    } else if ([binding isEqualToString:NSInitialValueBinding]) {
        [self setInitialValue:NSIsControllerMarker(value) ? nil : value];
    } else if ([binding isEqualToString:NSLocalizedKeyDictionaryBinding]) {
        [self setLocalizedKeyDictionary:[value isKindOfClass:[NSDictionary class]] ? value : nil];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentDictionaryBinding])
        return _dict;
    return [super _ferryValueForBinding:binding];
}
@end
