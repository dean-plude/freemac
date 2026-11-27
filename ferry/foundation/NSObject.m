/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: what NSObject gains from Foundation (descriptions and
 * simple key-value coding), NSError, NSException, NSAutoreleasePool, NSLog,
 * the NSStringFrom... functions, home and search paths, and the
 * old-style property list text that collections print as their description. */
#import "FInternal.h"
#include <pwd.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
#include <sys/time.h>

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *token);

NSString *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSString *const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
NSString *const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSString *const NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
NSString *const NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
NSString *const NSHelpAnchorErrorKey = @"NSHelpAnchor";
NSString *const NSURLErrorKey = @"NSURL";
NSString *const NSStringEncodingErrorKey = @"NSStringEncodingErrorKey";
NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
NSString *const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSString *const NSFilePathErrorKey = @"NSFilePath";
NSString *const NSUnderlyingErrorKey = @"NSUnderlyingError";
NSString *const NSMultipleUnderlyingErrorsKey = @"NSMultipleUnderlyingErrorsKey";
NSString *const NSGenericException = @"NSGenericException";
NSString *const NSRangeException = @"NSRangeException";
NSString *const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString *const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSString *const NSMallocException = @"NSMallocException";
NSString *const NSObjectInaccessibleException = @"NSObjectInaccessibleException";
NSString *const NSObjectNotAvailableException = @"NSObjectNotAvailableException";
NSString *const NSDestinationInvalidException = @"NSDestinationInvalidException";
NSString *const NSPortTimeoutException = @"NSPortTimeoutException";
NSString *const NSInvalidSendPortException = @"NSInvalidSendPortException";
NSString *const NSInvalidReceivePortException = @"NSInvalidReceivePortException";
NSString *const NSPortSendException = @"NSPortSendException";
NSString *const NSPortReceiveException = @"NSPortReceiveException";
NSString *const NSCharacterConversionException = @"NSCharacterConversionException";
NSString *const NSFileHandleOperationException = @"NSFileHandleOperationException";
NSString *const NSParseErrorException = @"NSParseErrorException";
NSString *const NSUndefinedKeyException = @"NSUnknownKeyException";

/* ---- descriptions ------------------------------------------------------------------- */

static BOOL plain_word(NSString *s)
{
    NSUInteger n = [s length];
    if (n == 0)
        return NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '$' ||
              c == '/' || c == ':' || c == '.' || c == '-'))
            return NO;
    }
    return YES;
}

static NSString *quoted(NSString *s)
{
    if (plain_word(s))
        return s;
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
        case '"': [out appendString:@"\\\""]; break;
        case '\\': [out appendString:@"\\\\"]; break;
        case '\n': [out appendString:@"\\n"]; break;
        case '\t': [out appendString:@"\\t"]; break;
        case '\r': [out appendString:@"\\r"]; break;
        default:
            if (c >= 0x80 || c < ' ')
                [out appendFormat:@"\\U%04x", c];
            else
                [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"\""];
    return out;
}

static void indent_to(NSMutableString *s, int level)
{
    for (int i = 0; i < level; i++)
        [s appendString:@"    "];
}

static NSString *describe_item(id obj, int indent)
{
    if ([obj isKindOfClass:[NSString class]])
        return quoted(obj);
    if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]] ||
        [obj isKindOfClass:[NSSet class]])
        return FDescribe(obj, indent);
    return [obj description];
}

NSString *FDescribe(id obj, int indent)
{
    NSMutableString *s = [NSMutableString string];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [obj allKeys];
        BOOL allStrings = YES;
        for (id k in keys)
            if (![k isKindOfClass:[NSString class]])
                allStrings = NO;
        if (allStrings)
            keys = [keys sortedArrayUsingSelector:@selector(compare:)];
        [s appendString:@"{\n"];
        for (id k in keys) {
            indent_to(s, indent + 1);
            [s appendFormat:@"%@ = %@;\n", describe_item(k, indent + 1), describe_item([obj objectForKey:k], indent + 1)];
        }
        indent_to(s, indent);
        [s appendString:@"}"];
        return s;
    }
    BOOL set = [obj isKindOfClass:[NSSet class]];
    NSArray *items = set ? [obj allObjects] : obj;
    [s appendString:set ? @"{(\n" : @"(\n"];
    NSUInteger n = [items count];
    for (NSUInteger i = 0; i < n; i++) {
        indent_to(s, indent + 1);
        [s appendString:describe_item([items objectAtIndex:i], indent + 1)];
        [s appendString:i + 1 < n ? @",\n" : @"\n"];
    }
    indent_to(s, indent);
    [s appendString:set ? @")}" : @")"];
    return s;
}

/* ---- NSObject ------------------------------------------------------------------------ */

/* The array mutableArrayValueForKey: answers (defined after NSObject's methods). */
@interface FKVCArrayProxy : NSMutableArray {
    id _object;
    NSString *_key;
    SEL _insert, _remove, _replace, _setter;
}
- (instancetype)_initWithObject:(id)object key:(NSString *)key;
@end
/* The set mutableSetValueForKey: answers. */
@interface FKVCSetProxy : NSMutableSet {
    id _object;
    NSString *_key;
    SEL _addOne, _removeOne, _addMany, _removeMany, _intersect, _setter;
}
- (instancetype)_initWithObject:(id)object key:(NSString *)key;
@end
/* The arrays and sets valueForKey: answers for a key an object gives only
 * through indexed or set accessors (countOf<Key> and the like), read
 * through them each time (freemac 1.225). */
@interface FKVCIndexedArray : NSArray {
    id _object;
    SEL _count, _at, _atIndexes;
}
- (instancetype)_initWithObject:(id)object count:(SEL)count at:(SEL)at atIndexes:(SEL)atIndexes;
@end
@interface FKVCAccessorSet : NSSet {
    id _object;
    SEL _count, _enumerator, _member;
}
- (instancetype)_initWithObject:(id)object count:(SEL)count enumerator:(SEL)enumerator member:(SEL)member;
@end


@implementation NSObject (NSObjectFoundation)
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p>", [self class], self]; }
- (NSString *)debugDescription { return [self description]; }
+ (NSString *)description { return [NSString stringWithUTF8String:class_getName(self)]; }
+ (NSString *)debugDescription { return [self description]; }
- (NSString *)className { return NSStringFromClass([self class]); }

/* ---- key-value coding ---------------------------------------------------------------
 * The search orders of Apple's "Key-Value Coding Programming Guide": for a
 * value, get<Key>, <key>, is<Key> and _<key>, then (when the class allows
 * it, as by default) the instance variables _<key>, _is<Key>, <key> and
 * is<Key>; for setting, set<Key>: and _set<Key>:, then the same variables.
 * Scalars, and points, sizes, rects and ranges, come and go as NSNumber
 * and NSValue. Setting a variable directly notifies observers unless the
 * class says not to; a setter notifies through key-value observing's
 * hidden subclass (NSKeyValueObserving.m). */

/* The boxed value of a scalar or struct at p, of type t. */
static id box_at(const void *p, const char *t)
{
    switch (*t) {
    case '@':
    case '#': return *(id *)p;
    case 'c': return [NSNumber numberWithChar:*(const char *)p];
    case 'B': return [NSNumber numberWithBool:*(const BOOL *)p];
    case 'C': return [NSNumber numberWithUnsignedChar:*(const unsigned char *)p];
    case 's': return [NSNumber numberWithShort:*(const short *)p];
    case 'S': return [NSNumber numberWithUnsignedShort:*(const unsigned short *)p];
    case 'i': return [NSNumber numberWithInt:*(const int *)p];
    case 'I': return [NSNumber numberWithUnsignedInt:*(const unsigned *)p];
    case 'q':
    case 'l': return [NSNumber numberWithLongLong:*(const long long *)p];
    case 'Q':
    case 'L': return [NSNumber numberWithUnsignedLongLong:*(const unsigned long long *)p];
    case 'f': return [NSNumber numberWithFloat:*(const float *)p];
    case 'd': return [NSNumber numberWithDouble:*(const double *)p];
    case '{':
        if (!strncmp(t, "{CGPoint=", 9) || !strncmp(t, "{_NSPoint=", 10))
            return [NSValue valueWithPoint:*(const NSPoint *)p];
        if (!strncmp(t, "{CGSize=", 8) || !strncmp(t, "{_NSSize=", 9))
            return [NSValue valueWithSize:*(const NSSize *)p];
        if (!strncmp(t, "{CGRect=", 8) || !strncmp(t, "{_NSRect=", 9))
            return [NSValue valueWithRect:*(const NSRect *)p];
        if (!strncmp(t, "{_NSRange=", 10))
            return [NSValue valueWithRange:*(const NSRange *)p];
        return nil;
    }
    return nil;
}

/* Stores a boxed value at p as type t; NO if the type isn't one KVC knows. */
static BOOL unbox_to(void *p, const char *t, id v)
{
    switch (*t) {
    case 'c': *(char *)p = [v charValue]; return YES;
    case 'B': *(BOOL *)p = [v boolValue]; return YES;
    case 'C': *(unsigned char *)p = [v unsignedCharValue]; return YES;
    case 's': *(short *)p = [v shortValue]; return YES;
    case 'S': *(unsigned short *)p = [v unsignedShortValue]; return YES;
    case 'i': *(int *)p = [v intValue]; return YES;
    case 'I': *(unsigned *)p = [v unsignedIntValue]; return YES;
    case 'q':
    case 'l': *(long long *)p = [v longLongValue]; return YES;
    case 'Q':
    case 'L': *(unsigned long long *)p = [v unsignedLongLongValue]; return YES;
    case 'f': *(float *)p = [v floatValue]; return YES;
    case 'd': *(double *)p = [v doubleValue]; return YES;
    case '{':
        if (!strncmp(t, "{CGPoint=", 9) || !strncmp(t, "{_NSPoint=", 10))
            *(NSPoint *)p = [v pointValue];
        else if (!strncmp(t, "{CGSize=", 8) || !strncmp(t, "{_NSSize=", 9))
            *(NSSize *)p = [v sizeValue];
        else if (!strncmp(t, "{CGRect=", 8) || !strncmp(t, "{_NSRect=", 9))
            *(NSRect *)p = [v rectValue];
        else if (!strncmp(t, "{_NSRange=", 10))
            *(NSRange *)p = [v rangeValue];
        else
            return NO;
        return YES;
    }
    return NO;
}

static BOOL is_pair(const char *t)
{
    return !strncmp(t, "{CGPoint=", 9) || !strncmp(t, "{_NSPoint=", 10) || !strncmp(t, "{CGSize=", 8) ||
           !strncmp(t, "{_NSSize=", 9);
}
static BOOL is_rect(const char *t) { return !strncmp(t, "{CGRect=", 8) || !strncmp(t, "{_NSRect=", 9); }
static BOOL is_range(const char *t) { return !strncmp(t, "{_NSRange=", 10); }

/* The value a getter returns, boxed. */
static id box(id self, SEL sel, const char *t)
{
    switch (*t) {
    case '@':
    case '#': return ((id (*)(id, SEL))objc_msgSend)(self, sel);
    case 'c':
    case 'B':
    case 'C': {
        unsigned char v = ((unsigned char (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case 's':
    case 'S': {
        unsigned short v = ((unsigned short (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case 'i':
    case 'I': {
        unsigned v = ((unsigned (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case 'q':
    case 'l':
    case 'Q':
    case 'L': {
        long long v = ((long long (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case 'f': {
        float v = ((float (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case 'd': {
        double v = ((double (*)(id, SEL))objc_msgSend)(self, sel);
        return box_at(&v, t);
    }
    case '{':
        if (is_pair(t)) {
            NSPoint v = ((NSPoint (*)(id, SEL))objc_msgSend)(self, sel);
            return box_at(&v, t);
        }
        if (is_rect(t)) {
            NSRect v = ((NSRect (*)(id, SEL))objc_msgSend_stret)(self, sel);
            return box_at(&v, t);
        }
        if (is_range(t)) {
            NSRange v = ((NSRange (*)(id, SEL))objc_msgSend)(self, sel);
            return box_at(&v, t);
        }
        return nil;
    }
    return nil;
}

static NSString *capitalized(NSString *key)
{
    return [[[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]];
}

/* The instance variable KVC would use for key: _<key>, _is<Key>, <key>, is<Key>. */
static Ivar kvc_ivar(Class cls, NSString *key)
{
    if (![cls accessInstanceVariablesDirectly])
        return NULL;
    NSString *Key = capitalized(key);
    NSString *names[] = {[@"_" stringByAppendingString:key], [@"_is" stringByAppendingString:Key], key,
                         [@"is" stringByAppendingString:Key]};
    for (int i = 0; i < 4; i++) {
        Ivar v = class_getInstanceVariable(cls, [names[i] UTF8String]);
        if (v)
            return v;
    }
    return NULL;
}

/* A getter with no arguments named for key, if there is one. */
static SEL kvc_getter(Class cls, NSString *key, Method *out)
{
    NSString *Key = capitalized(key);
    NSString *names[] = {[@"get" stringByAppendingString:Key], key, [@"is" stringByAppendingString:Key],
                         [@"_" stringByAppendingString:key]};
    for (int i = 0; i < 4; i++) {
        SEL sel = NSSelectorFromString(names[i]);
        Method m = class_getInstanceMethod(cls, sel);
        if (m && method_getNumberOfArguments(m) == 2) {
            *out = m;
            return sel;
        }
    }
    return NULL;
}

/* Sends a one-argument setter whose argument has type t; NO if KVC can't. */
static BOOL send_setter(id self, SEL sel, const char *t, id value)
{
    switch (*t) {
    case '@':
    case '#': ((void (*)(id, SEL, id))objc_msgSend)(self, sel, value); return YES;
    case 'B': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value boolValue]); return YES;
    case 'c':
    case 'C': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value charValue]); return YES;
    case 's':
    case 'S': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value shortValue]); return YES;
    case 'i':
    case 'I': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value intValue]); return YES;
    case 'q':
    case 'Q':
    case 'l':
    case 'L': ((void (*)(id, SEL, long long))objc_msgSend)(self, sel, [value longLongValue]); return YES;
    case 'f': ((void (*)(id, SEL, float))objc_msgSend)(self, sel, [value floatValue]); return YES;
    case 'd': ((void (*)(id, SEL, double))objc_msgSend)(self, sel, [value doubleValue]); return YES;
    case '{':
        if (!strncmp(t, "{CGSize=", 8) || !strncmp(t, "{_NSSize=", 9)) {
            ((void (*)(id, SEL, NSSize))objc_msgSend)(self, sel, [value sizeValue]);
            return YES;
        }
        if (is_pair(t)) {
            ((void (*)(id, SEL, NSPoint))objc_msgSend)(self, sel, [value pointValue]);
            return YES;
        }
        if (is_rect(t)) {
            ((void (*)(id, SEL, NSRect))objc_msgSend)(self, sel, [value rectValue]);
            return YES;
        }
        if (is_range(t)) {
            ((void (*)(id, SEL, NSRange))objc_msgSend)(self, sel, [value rangeValue]);
            return YES;
        }
        return NO;
    }
    return NO;
}

- (id)valueForKey:(NSString *)key
{
    if (![key length])
        return [self valueForUndefinedKey:key];
    Class cls = object_getClass(self);
    Method m = NULL;
    SEL sel = kvc_getter(cls, key, &m);
    if (sel) {
        char t[256];
        method_getReturnType(m, t, sizeof t);
        return box(self, sel, t);
    }
    /* Then, as Apple's guide orders it, countOf<Key> with objectIn<Key>AtIndex:
     * or <key>AtIndexes: makes an array, and countOf<Key> with
     * enumeratorOf<Key> and memberOf<Key>: a set. */
    NSString *Key = capitalized(key);
    SEL count = NSSelectorFromString([@"countOf" stringByAppendingString:Key]);
    if (class_respondsToSelector(cls, count)) {
        SEL at = NSSelectorFromString([NSString stringWithFormat:@"objectIn%@AtIndex:", Key]);
        SEL atIndexes = NSSelectorFromString([key stringByAppendingString:@"AtIndexes:"]);
        BOOL hasAt = class_respondsToSelector(cls, at), hasAtIndexes = class_respondsToSelector(cls, atIndexes);
        if (hasAt || hasAtIndexes)
            return [[[FKVCIndexedArray alloc] _initWithObject:self
                                                        count:count
                                                           at:hasAt ? at : NULL
                                                    atIndexes:hasAtIndexes ? atIndexes : NULL] autorelease];
        SEL enumerator = NSSelectorFromString([@"enumeratorOf" stringByAppendingString:Key]);
        SEL member = NSSelectorFromString([NSString stringWithFormat:@"memberOf%@:", Key]);
        if (class_respondsToSelector(cls, enumerator) && class_respondsToSelector(cls, member))
            return [[[FKVCAccessorSet alloc] _initWithObject:self count:count enumerator:enumerator
                                                      member:member] autorelease];
    }
    Ivar v = kvc_ivar(cls, key);
    if (v)
        return box_at((char *)self + ivar_getOffset(v), ivar_getTypeEncoding(v));
    return [self valueForUndefinedKey:key];
}
- (id)valueForUndefinedKey:(NSString *)key
{
    FRaise(@"NSUnknownKeyException", @"[<%@ %p> valueForUndefinedKey:]: this class is not key value coding-compliant "
                                     @"for the key %@.",
           [self class], self, key);
}
+ (BOOL)accessInstanceVariablesDirectly { return YES; }

- (void)setValue:(id)value forKey:(NSString *)key
{
    if (![key length]) {
        [self setValue:value forUndefinedKey:key];
        return;
    }
    Class cls = object_getClass(self);
    NSString *Key = capitalized(key);
    NSString *setters[] = {[NSString stringWithFormat:@"set%@:", Key], [NSString stringWithFormat:@"_set%@:", Key]};
    for (int i = 0; i < 2; i++) {
        SEL sel = NSSelectorFromString(setters[i]);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m || method_getNumberOfArguments(m) != 3)
            continue;
        char t[256];
        method_getArgumentType(m, 2, t, sizeof t);
        if (!value && *t != '@' && *t != '#') {
            [self setNilValueForKey:key];
            return;
        }
        if (send_setter(self, sel, t, value))
            return;
    }
    Ivar v = kvc_ivar(cls, key);
    if (v) {
        const char *t = ivar_getTypeEncoding(v);
        if (*t != '@' && !value) {
            [self setNilValueForKey:key];
            return;
        }
        BOOL notifies = [[self class] automaticallyNotifiesObserversForKey:key];
        if (notifies)
            [self willChangeValueForKey:key];
        if (*t == '@') {
            id old = object_getIvar(self, v);
            object_setIvar(self, v, [value retain]);
            [old release];
        } else {
            unbox_to((char *)self + ivar_getOffset(v), t, value);
        }
        if (notifies)
            [self didChangeValueForKey:key];
        return;
    }
    [self setValue:value forUndefinedKey:key];
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    FRaise(@"NSUnknownKeyException", @"[<%@ %p> setValue:forUndefinedKey:]: this class is not key value "
                                     @"coding-compliant for the key %@.",
           [self class], self, key);
}
- (void)setNilValueForKey:(NSString *)key
{
    FRaise(NSInvalidArgumentException, @"[<%@ %p> setNilValueForKey]: could not set nil as the value for the key %@.",
           [self class], self, key);
}

/* validate<Key>:error:, if the class has it. */
- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
    if (![key length])
        return YES;
    SEL sel = NSSelectorFromString([NSString stringWithFormat:@"validate%@:error:", capitalized(key)]);
    if ([self respondsToSelector:sel])
        return ((BOOL (*)(id, SEL, id *, NSError **))objc_msgSend)(self, sel, value, error);
    return YES;
}
- (BOOL)validateValue:(id *)value forKeyPath:(NSString *)path error:(NSError **)error
{
    NSRange dot = [path rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        return [self validateValue:value forKey:path error:error];
    return [[self valueForKeyPath:[path substringToIndex:dot.location]]
        validateValue:value
               forKey:[path substringFromIndex:dot.location + 1]
                error:error];
}

- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in keys)
        [d setObject:[self valueForKey:k] ?: (id)[NSNull null] forKey:k];
    return d;
}
- (void)setValuesForKeysWithDictionary:(NSDictionary *)values
{
    for (NSString *k in values) {
        id v = [values objectForKey:k];
        [self setValue:v == [NSNull null] ? nil : v forKey:k];
    }
}

/* "a.b.c": each key in turn, from the object the one before gave. */
- (id)valueForKeyPath:(NSString *)path
{
    NSRange dot = [path rangeOfString:@"."];
    if (dot.location == NSNotFound)
        return [self valueForKey:path];
    id first = [self valueForKey:[path substringToIndex:dot.location]];
    return [first valueForKeyPath:[path substringFromIndex:dot.location + 1]];
}
- (void)setValue:(id)value forKeyPath:(NSString *)path
{
    NSRange dot = [path rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound) {
        [self setValue:value forKey:path];
        return;
    }
    [[self valueForKeyPath:[path substringToIndex:dot.location]] setValue:value
                                                                   forKey:[path substringFromIndex:dot.location + 1]];
}

- (NSMutableArray *)mutableArrayValueForKey:(NSString *)key
{
    return [[[FKVCArrayProxy alloc] _initWithObject:self key:key] autorelease];
}
- (NSMutableArray *)mutableArrayValueForKeyPath:(NSString *)path
{
    NSRange dot = [path rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        return [self mutableArrayValueForKey:path];
    return [[self valueForKeyPath:[path substringToIndex:dot.location]]
        mutableArrayValueForKey:[path substringFromIndex:dot.location + 1]];
}
- (NSMutableSet *)mutableSetValueForKey:(NSString *)key
{
    return [[[FKVCSetProxy alloc] _initWithObject:self key:key] autorelease];
}
- (NSMutableSet *)mutableSetValueForKeyPath:(NSString *)path
{
    NSRange dot = [path rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        return [self mutableSetValueForKey:path];
    return [[self valueForKeyPath:[path substringToIndex:dot.location]]
        mutableSetValueForKey:[path substringFromIndex:dot.location + 1]];
}
@end

/* ---- valueForKey: through indexed and set accessors ------------------------------- */
@implementation FKVCIndexedArray
- (instancetype)_initWithObject:(id)object count:(SEL)count at:(SEL)at atIndexes:(SEL)atIndexes
{
    if ((self = [super init])) {
        _object = [object retain];
        _count = count;
        _at = at;
        _atIndexes = atIndexes;
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [super dealloc];
}
- (NSUInteger)count { return ((NSUInteger (*)(id, SEL))objc_msgSend)(_object, _count); }
- (id)objectAtIndex:(NSUInteger)i
{
    if (i >= [self count])
        FRaise(NSRangeException, @"-[NSArray objectAtIndex:]: index %lu beyond bounds [0 .. %lu]", (unsigned long)i,
               (unsigned long)[self count] - 1);
    if (_at)
        return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(_object, _at, i);
    NSArray *one = ((id (*)(id, SEL, id))objc_msgSend)(_object, _atIndexes, [NSIndexSet indexSetWithIndex:i]);
    return [one objectAtIndex:0];
}
@end

@implementation FKVCAccessorSet
- (instancetype)_initWithObject:(id)object count:(SEL)count enumerator:(SEL)enumerator member:(SEL)member
{
    if ((self = [super init])) {
        _object = [object retain];
        _count = count;
        _enumerator = enumerator;
        _member = member;
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [super dealloc];
}
- (NSUInteger)count { return ((NSUInteger (*)(id, SEL))objc_msgSend)(_object, _count); }
- (NSEnumerator *)objectEnumerator { return ((id (*)(id, SEL))objc_msgSend)(_object, _enumerator); }
- (id)member:(id)obj { return ((id (*)(id, SEL, id))objc_msgSend)(_object, _member, obj); }
@end

/* ---- mutableArrayValueForKey: -----------------------------------------------------
 * A mutable array standing for an object's to-many key. As Apple's guide
 * describes, changes go through the object's indexed mutators
 * (insertObject:in<Key>AtIndex: and removeObjectFrom<Key>AtIndex:, and
 * replaceObjectIn<Key>AtIndex:withObject: if it has it), else through
 * set<Key>: with a changed copy, else straight to an NSMutableArray
 * instance variable, announced to observers as insertions, removals and
 * replacements at their indexes. */
@implementation FKVCArrayProxy
- (instancetype)_initWithObject:(id)object key:(NSString *)key
{
    if ((self = [super init])) {
        _object = [object retain];
        _key = [key copy];
        NSString *Key = capitalized(key);
        SEL ins = NSSelectorFromString([NSString stringWithFormat:@"insertObject:in%@AtIndex:", Key]);
        SEL rem = NSSelectorFromString([NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", Key]);
        if ([object respondsToSelector:ins] && [object respondsToSelector:rem]) {
            _insert = ins;
            _remove = rem;
            SEL rep = NSSelectorFromString([NSString stringWithFormat:@"replaceObjectIn%@AtIndex:withObject:", Key]);
            if ([object respondsToSelector:rep])
                _replace = rep;
        } else {
            SEL set = NSSelectorFromString([NSString stringWithFormat:@"set%@:", Key]);
            if ([object respondsToSelector:set])
                _setter = set;
        }
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [_key release];
    [super dealloc];
}
- (NSArray *)_current { return [_object valueForKey:_key]; }
- (NSUInteger)count { return [[self _current] count]; }
- (id)objectAtIndex:(NSUInteger)i { return [[self _current] objectAtIndex:i]; }
/* The array itself, when it is kept straight in an instance variable. */
- (NSMutableArray *)_storage
{
    Ivar v = kvc_ivar(object_getClass(_object), _key);
    if (!v || ivar_getTypeEncoding(v)[0] != '@')
        FRaise(@"NSUnknownKeyException", @"[<%@ %p> mutableArrayValueForKey:]: the key %@ can't be changed.",
               [_object class], _object, _key);
    id a = object_getIvar(_object, v);
    if (!a) {
        a = [[NSMutableArray alloc] init];
        object_setIvar(_object, v, a);
    }
    if (![a isKindOfClass:[NSMutableArray class]])
        FRaise(NSInternalInconsistencyException, @"the instance variable for %@ isn't a mutable array", _key);
    return a;
}
- (void)_change:(NSKeyValueChange)kind at:(NSUInteger)i with:(id)obj
{
    if (_setter) {
        NSMutableArray *copy = [[[self _current] mutableCopy] autorelease] ?: [NSMutableArray array];
        if (kind == NSKeyValueChangeInsertion)
            [copy insertObject:obj atIndex:i];
        else if (kind == NSKeyValueChangeRemoval)
            [copy removeObjectAtIndex:i];
        else
            [copy replaceObjectAtIndex:i withObject:obj];
        ((void (*)(id, SEL, id))objc_msgSend)(_object, _setter, copy);
        return;
    }
    NSMutableArray *a = [self _storage];
    BOOL notifies = [[_object class] automaticallyNotifiesObserversForKey:_key];
    NSIndexSet *at = [NSIndexSet indexSetWithIndex:i];
    if (notifies)
        [_object willChange:kind valuesAtIndexes:at forKey:_key];
    if (kind == NSKeyValueChangeInsertion)
        [a insertObject:obj atIndex:i];
    else if (kind == NSKeyValueChangeRemoval)
        [a removeObjectAtIndex:i];
    else
        [a replaceObjectAtIndex:i withObject:obj];
    if (notifies)
        [_object didChange:kind valuesAtIndexes:at forKey:_key];
}
- (void)insertObject:(id)obj atIndex:(NSUInteger)i
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[NSKeyValueArray insertObject:atIndex:]: object cannot be nil");
    if (_insert)
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(_object, _insert, obj, i);
    else
        [self _change:NSKeyValueChangeInsertion at:i with:obj];
}
- (void)removeObjectAtIndex:(NSUInteger)i
{
    if (_remove)
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(_object, _remove, i);
    else
        [self _change:NSKeyValueChangeRemoval at:i with:nil];
}
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)obj
{
    if (_replace)
        ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(_object, _replace, i, obj);
    else if (_insert) {
        [obj retain];
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(_object, _remove, i);
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(_object, _insert, obj, i);
        [obj release];
    } else
        [self _change:NSKeyValueChangeReplacement at:i with:obj];
}
@end

/* ---- mutableSetValueForKey: -------------------------------------------------------
 * A mutable set standing for an object's unordered to-many key, searched
 * as Apple's guide orders it: the object's add<Key>Object: and
 * remove<Key>Object: (or add<Key>: and remove<Key>:, with intersect<Key>:
 * if it has it), else set<Key>: with a changed copy, else an NSMutableSet
 * instance variable changed directly and announced to observers with the
 * set mutation kinds. */
@implementation FKVCSetProxy
- (instancetype)initWithObjects:(const id[])objects count:(NSUInteger)count { return self; }
- (instancetype)_initWithObject:(id)object key:(NSString *)key
{
    if ((self = [super init])) {
        _object = [object retain];
        _key = [key copy];
        NSString *Key = capitalized(key);
#define FIND(var, fmt)                                                     \
    do {                                                                   \
        SEL s_ = NSSelectorFromString([NSString stringWithFormat:fmt, Key]); \
        if ([object respondsToSelector:s_])                                \
            var = s_;                                                      \
    } while (0)
        FIND(_addOne, @"add%@Object:");
        FIND(_removeOne, @"remove%@Object:");
        FIND(_addMany, @"add%@:");
        FIND(_removeMany, @"remove%@:");
        FIND(_intersect, @"intersect%@:");
        if (!((_addOne || _addMany) && (_removeOne || _removeMany))) {
            _addOne = _removeOne = _addMany = _removeMany = _intersect = NULL;
            FIND(_setter, @"set%@:");
        }
#undef FIND
    }
    return self;
}
- (void)dealloc
{
    [_object release];
    [_key release];
    [super dealloc];
}
- (NSSet *)_current
{
    id v = [_object valueForKey:_key];
    if ([v isKindOfClass:[NSArray class]])
        v = [NSSet setWithArray:v];
    return v;
}
- (NSUInteger)count { return [[self _current] count]; }
- (id)member:(id)obj { return [[self _current] member:obj]; }
- (NSArray *)allObjects { return [[self _current] allObjects] ?: [NSArray array]; }
- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)len
{
    /* a snapshot, kept by the pool around the loop */
    if (!state->state)
        state->extra[0] = (unsigned long)[self allObjects];
    return [(NSArray *)state->extra[0] countByEnumeratingWithState:state objects:buffer count:len];
}
/* The set itself, when it is kept straight in an instance variable. */
- (NSMutableSet *)_storage
{
    Ivar v = kvc_ivar(object_getClass(_object), _key);
    if (!v || ivar_getTypeEncoding(v)[0] != '@')
        FRaise(@"NSUnknownKeyException", @"[<%@ %p> mutableSetValueForKey:]: the key %@ can't be changed.",
               [_object class], _object, _key);
    id a = object_getIvar(_object, v);
    if (!a) {
        a = [[NSMutableSet alloc] init];
        object_setIvar(_object, v, a);
    }
    if (![a isKindOfClass:[NSMutableSet class]])
        FRaise(NSInternalInconsistencyException, @"the instance variable for %@ isn't a mutable set", _key);
    return a;
}
/* One change of the set, through whichever way the object offers. */
- (void)_mutate:(NSKeyValueSetMutationKind)kind with:(NSSet *)objs
{
    if (_addOne || _addMany) {
        switch (kind) {
        case NSKeyValueUnionSetMutation:
            /* one object goes through the one-object method when there is one */
            if (_addMany && !(_addOne && [objs count] == 1))
                ((void (*)(id, SEL, id))objc_msgSend)(_object, _addMany, objs);
            else
                for (id o in objs)
                    ((void (*)(id, SEL, id))objc_msgSend)(_object, _addOne, o);
            return;
        case NSKeyValueMinusSetMutation:
            if (_removeMany && !(_removeOne && [objs count] == 1))
                ((void (*)(id, SEL, id))objc_msgSend)(_object, _removeMany, objs);
            else
                for (id o in objs)
                    ((void (*)(id, SEL, id))objc_msgSend)(_object, _removeOne, o);
            return;
        case NSKeyValueIntersectSetMutation:
        case NSKeyValueSetSetMutation: {
            if (kind == NSKeyValueIntersectSetMutation && _intersect) {
                ((void (*)(id, SEL, id))objc_msgSend)(_object, _intersect, objs);
                return;
            }
            NSMutableSet *gone = [NSMutableSet set];
            for (id o in [self allObjects])
                if (![objs containsObject:o])
                    [gone addObject:o];
            if ([gone count])
                [self _mutate:NSKeyValueMinusSetMutation with:gone];
            if (kind == NSKeyValueSetSetMutation) {
                NSMutableSet *come = [NSMutableSet set];
                NSSet *now = [self _current];
                for (id o in objs)
                    if (![now containsObject:o])
                        [come addObject:o];
                if ([come count])
                    [self _mutate:NSKeyValueUnionSetMutation with:come];
            }
            return;
        }
        }
    }
    if (_setter) {
        NSMutableSet *copy = [[[self _current] mutableCopy] autorelease] ?: [NSMutableSet set];
        switch (kind) {
        case NSKeyValueUnionSetMutation: [copy unionSet:objs]; break;
        case NSKeyValueMinusSetMutation: [copy minusSet:objs]; break;
        case NSKeyValueIntersectSetMutation: [copy intersectSet:objs]; break;
        case NSKeyValueSetSetMutation: copy = [[objs mutableCopy] autorelease]; break;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(_object, _setter, copy);
        return;
    }
    NSMutableSet *set = [self _storage];
    BOOL notifies = [[_object class] automaticallyNotifiesObserversForKey:_key];
    if (notifies)
        [_object willChangeValueForKey:_key withSetMutation:kind usingObjects:objs];
    switch (kind) {
    case NSKeyValueUnionSetMutation: [set unionSet:objs]; break;
    case NSKeyValueMinusSetMutation: [set minusSet:objs]; break;
    case NSKeyValueIntersectSetMutation: [set intersectSet:objs]; break;
    case NSKeyValueSetSetMutation:
        [set removeAllObjects];
        [set unionSet:objs];
        break;
    }
    if (notifies)
        [_object didChangeValueForKey:_key withSetMutation:kind usingObjects:objs];
}
- (void)addObject:(id)obj
{
    if (!obj)
        FRaise(NSInvalidArgumentException, @"*** -[NSKeyValueSet addObject:]: object cannot be nil");
    [self _mutate:NSKeyValueUnionSetMutation with:[NSSet setWithObject:obj]];
}
- (void)removeObject:(id)obj
{
    if (obj)
        [self _mutate:NSKeyValueMinusSetMutation with:[NSSet setWithObject:obj]];
}
- (void)addObjectsFromArray:(NSArray *)array { [self _mutate:NSKeyValueUnionSetMutation with:[NSSet setWithArray:array]]; }
- (void)unionSet:(NSSet *)other { [self _mutate:NSKeyValueUnionSetMutation with:other ?: [NSSet set]]; }
- (void)minusSet:(NSSet *)other { [self _mutate:NSKeyValueMinusSetMutation with:other ?: [NSSet set]]; }
- (void)intersectSet:(NSSet *)other { [self _mutate:NSKeyValueIntersectSetMutation with:other ?: [NSSet set]]; }
- (void)setSet:(NSSet *)other { [self _mutate:NSKeyValueSetSetMutation with:other ?: [NSSet set]]; }
- (void)removeAllObjects { [self _mutate:NSKeyValueSetSetMutation with:[NSSet set]]; }
@end

/* ---- collection operators -----------------------------------------------------------
 * In a key path, "@op.rest" applied to an array or a set, as Apple's
 * "Key-Value Coding Programming Guide" describes: @count; @sum and @avg
 * (nil counting as 0), @min and @max (by compare:, nil left out); and the
 * unions, of the values (@unionOfObjects, @distinctUnionOfObjects) or of
 * the arrays or sets the elements give (@unionOfArrays,
 * @distinctUnionOfArrays, @distinctUnionOfSets). The unions leave nil out;
 * a set gives a set. */

static BOOL is_integer_number(id v)
{
    if (![v isKindOfClass:[NSNumber class]])
        return NO;
    const char *t = [v objCType];
    return t && strchr("cCsSiIlLqQB", *t);
}

static id collection_operator(id collection, NSString *path)
{
    NSRange dot = [path rangeOfString:@"."];
    NSString *op = dot.location == NSNotFound ? path : [path substringToIndex:dot.location];
    NSString *right = dot.location == NSNotFound ? nil : [path substringFromIndex:dot.location + 1];
    BOOL isSet = [collection isKindOfClass:[NSSet class]];
    NSArray *items = isSet ? [collection allObjects] : collection;
    if ([op isEqualToString:@"@count"])
        return @([items count]);
    NSMutableArray *values = [NSMutableArray array];   /* NSNull for nil */
    for (id o in items) {
        id v = right ? [o valueForKeyPath:right] : o;
        [values addObject:v ?: [NSNull null]];
    }
    if ([op isEqualToString:@"@sum"] || [op isEqualToString:@"@avg"]) {
        BOOL decimals = NO;   /* with a decimal number among them, in base 10 */
        for (id v in values)
            decimals |= [v isKindOfClass:[NSDecimalNumber class]];
        if (decimals) {
            NSDecimalNumber *total = [NSDecimalNumber zero];
            for (id v in values) {
                if (v == [NSNull null])
                    continue;
                NSNumber *n = [v isKindOfClass:[NSNumber class]] ? v : @([v doubleValue]);
                total = [total decimalNumberByAdding:[NSDecimalNumber decimalNumberWithDecimal:[n decimalValue]]];
            }
            if ([op isEqualToString:@"@sum"])
                return total;
            return [total decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithMantissa:[values count]
                                                                                       exponent:0
                                                                                     isNegative:NO]];
        }
        BOOL integers = YES;
        long long isum = 0;
        double dsum = 0;
        for (id v in values) {
            if (v == [NSNull null])
                continue;
            if (!is_integer_number(v))
                integers = NO;
            isum += [v longLongValue];
            dsum += [v doubleValue];
        }
        if ([op isEqualToString:@"@sum"])
            return integers ? @(isum) : @(dsum);
        if (![values count])
            return @0;
        double avg = dsum / (double)[values count];
        return integers && avg == floor(avg) ? @((long long)avg) : @(avg);
    }
    if ([op isEqualToString:@"@max"] || [op isEqualToString:@"@min"]) {
        BOOL max = [op isEqualToString:@"@max"];
        id best = nil;
        for (id v in values) {
            if (v == [NSNull null])
                continue;
            if (!best) {
                best = v;
                continue;
            }
            NSComparisonResult r = (NSComparisonResult)((NSInteger(*)(id, SEL, id))objc_msgSend)(v, @selector(compare:), best);
            if ((max && r == NSOrderedDescending) || (!max && r == NSOrderedAscending))
                best = v;
        }
        return best;
    }
    BOOL distinct = [op hasPrefix:@"@distinct"];
    NSMutableArray *out = [NSMutableArray array];
    void (^put)(id) = ^(id v) {
        if (v == [NSNull null] || !v)
            return;
        if (distinct && [out containsObject:v])
            return;
        [out addObject:v];
    };
    if ([op isEqualToString:@"@unionOfObjects"] || [op isEqualToString:@"@distinctUnionOfObjects"]) {
        for (id v in values)
            put(v);
    } else if ([op isEqualToString:@"@unionOfArrays"] || [op isEqualToString:@"@distinctUnionOfArrays"] ||
               [op isEqualToString:@"@distinctUnionOfSets"]) {
        for (id v in values) {
            if ([v isKindOfClass:[NSSet class]])
                v = [v allObjects];
            if ([v isKindOfClass:[NSArray class]])
                for (id x in v)
                    put(x);
        }
        if ([op isEqualToString:@"@distinctUnionOfSets"])
            return [NSSet setWithArray:out];
    } else {
        FRaise(@"NSUnknownKeyException", @"[<%@ %p> valueForKeyPath:]: this class does not implement the %@ operation.",
               [collection class], collection, [op substringFromIndex:1]);
    }
    return isSet ? (id)[NSSet setWithArray:out] : (id)[NSArray arrayWithArray:out];
}

@implementation NSArray (FKVCCollections)
- (id)valueForKeyPath:(NSString *)path
{
    if ([path hasPrefix:@"@"])
        return collection_operator(self, path);
    return [super valueForKeyPath:path];
}
/* each element's key is set */
- (void)setValue:(id)value forKey:(NSString *)key
{
    for (id o in self)
        [o setValue:value forKey:key];
}
@end

@implementation NSSet (FKVCCollections)
- (id)valueForKey:(NSString *)key
{
    NSMutableSet *m = [NSMutableSet set];
    for (id o in self) {
        id v = [o valueForKey:key];
        if (v)
            [m addObject:v];
    }
    return m;
}
- (id)valueForKeyPath:(NSString *)path
{
    if ([path hasPrefix:@"@"])
        return collection_operator(self, path);
    return [super valueForKeyPath:path];
}
- (void)setValue:(id)value forKey:(NSString *)key
{
    for (id o in self)
        [o setValue:value forKey:key];
}
@end

/* ---- NSComparisonMethods: isEqual:, and compare: where the object has it ---------- */

@implementation NSObject (NSComparisonMethods)
static NSComparisonResult compare_objects(id a, id b)
{
    if ([a respondsToSelector:@selector(compare:)])
        return (NSComparisonResult)[(NSString *)a compare:b];
    return [a isEqual:b] ? NSOrderedSame : (NSComparisonResult)2; /* neither smaller nor larger */
}
- (BOOL)isEqualTo:(id)object { return [self isEqual:object]; }
- (BOOL)isNotEqualTo:(id)object { return ![self isEqual:object]; }
- (BOOL)isLessThan:(id)object { return compare_objects(self, object) == NSOrderedAscending; }
- (BOOL)isLessThanOrEqualTo:(id)object { return compare_objects(self, object) <= NSOrderedSame; }
- (BOOL)isGreaterThan:(id)object { return compare_objects(self, object) == NSOrderedDescending; }
- (BOOL)isGreaterThanOrEqualTo:(id)object
{
    NSComparisonResult r = compare_objects(self, object);
    return r == NSOrderedSame || r == NSOrderedDescending;
}
@end

/* ---- NSError ----------------------------------------------------------------------- */

@implementation NSError {
    NSString *_domain;
    NSInteger _code;
    NSDictionary *_userInfo;
}
+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
{
    return [[[self alloc] initWithDomain:domain code:code userInfo:dict] autorelease];
}
- (instancetype)initWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
{
    _domain = [domain copy];
    _code = code;
    _userInfo = [dict copy];
    return self;
}
- (void)dealloc
{
    [_domain release];
    [_userInfo release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSErrorDomain)domain { return _domain; }
- (NSInteger)code { return _code; }
- (NSDictionary *)userInfo { return _userInfo ?: [NSDictionary dictionary]; }
- (NSString *)localizedDescription
{
    NSString *d = [_userInfo objectForKey:NSLocalizedDescriptionKey];
    if (d)
        return d;
    NSString *file = [[_userInfo objectForKey:NSFilePathErrorKey] lastPathComponent];
    if ([_domain isEqualToString:NSPOSIXErrorDomain])
        return [NSString stringWithFormat:@"The operation couldn’t be completed. %s", strerror((int)_code)];
    if ([_domain isEqualToString:NSCocoaErrorDomain] && file) {
        switch (_code) {
        case NSFileReadNoSuchFileError:
            return [NSString stringWithFormat:@"The file “%@” couldn’t be opened because there is no "
                                              @"such file.",
                                              file];
        case 257:
            return [NSString stringWithFormat:@"The file “%@” couldn’t be opened because you don’t "
                                              @"have permission to view it.",
                                              file];
        case NSFileWriteFileExistsError:
            return [NSString stringWithFormat:@"The file “%@” couldn’t be saved because a file with "
                                              @"the same name already exists.",
                                              file];
        }
    }
    return [NSString stringWithFormat:@"The operation couldn’t be completed. (%@ error %ld.)", _domain, (long)_code];
}
- (NSString *)localizedFailureReason { return [_userInfo objectForKey:NSLocalizedFailureReasonErrorKey]; }
- (NSString *)localizedRecoverySuggestion { return [_userInfo objectForKey:NSLocalizedRecoverySuggestionErrorKey]; }
- (NSArray *)localizedRecoveryOptions { return [_userInfo objectForKey:NSLocalizedRecoveryOptionsErrorKey]; }
- (id)recoveryAttempter { return [_userInfo objectForKey:NSRecoveryAttempterErrorKey]; }
- (NSString *)helpAnchor { return [_userInfo objectForKey:NSHelpAnchorErrorKey]; }
- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\"", _domain, (long)_code,
                                                            [self localizedDescription]];
    if ([_userInfo count]) {
        NSArray *keys = [[_userInfo allKeys] sortedArrayUsingSelector:@selector(compare:)];
        [s appendString:@" UserInfo={"];
        for (NSUInteger i = 0; i < [keys count]; i++)
            [s appendFormat:@"%@%@=%@", i ? @", " : @"", [keys objectAtIndex:i],
                            [_userInfo objectForKey:[keys objectAtIndex:i]]];
        [s appendString:@"}"];
    }
    return s;
}
@end

NSError *FPosixError(int err, NSString *path)
{
    NSInteger code;
    switch (err) {
    case ENOENT: code = NSFileReadNoSuchFileError; break;
    case EACCES:
    case EPERM: code = 257; break;
    case EEXIST: code = NSFileWriteFileExistsError; break;
    default: code = NSFileReadUnknownError; break;
    }
    NSError *under = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:under forKey:NSUnderlyingErrorKey];
    if (path)
        [info setObject:path forKey:NSFilePathErrorKey];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

void FSetError(NSError **out, NSError *e)
{
    if (out)
        *out = e;
}

/* ---- NSException ------------------------------------------------------------------ */

typedef void NSUncaughtExceptionHandler(NSException *exception);
static NSUncaughtExceptionHandler *uncaught_handler;

F_EXPORT void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler) { uncaught_handler = handler; }
F_EXPORT NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void) { return uncaught_handler; }

/* What the runtime calls when nothing catches an exception: the program's
 * own handler, then the message a Mac prints before the program ends. */
static void report_uncaught(id obj)
{
    BOOL isException = [obj isKindOfClass:[NSException class]];
    if (uncaught_handler && isException)
        uncaught_handler(obj);
    fflush(stdout);
    if (isException)
        fprintf(stderr, "*** Terminating app due to uncaught exception '%s', reason: '%s'\n",
                [[(NSException *)obj name] UTF8String], [[obj description] UTF8String]);
    else
        fprintf(stderr, "*** Terminating app due to uncaught exception of class '%s'\n", object_getClassName(obj));
}
__attribute__((constructor)) static void exceptions_init(void) { objc_setUncaughtExceptionHandler(report_uncaught); }

@implementation NSException {
    NSString *_name, *_reason;
    NSDictionary *_userInfo;
}
+ (NSException *)exceptionWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo
{
    return [[[self alloc] initWithName:name reason:reason userInfo:userInfo] autorelease];
}
+ (void)raise:(NSExceptionName)name format:(NSString *)format arguments:(va_list)args
{
    [[self exceptionWithName:name reason:FFormat(format, args) userInfo:nil] raise];
}
+ (void)raise:(NSExceptionName)name format:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSString *reason = FFormat(format, ap);
    va_end(ap);
    [[self exceptionWithName:name reason:reason userInfo:nil] raise];
}
- (instancetype)initWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo
{
    _name = [name copy];
    _reason = [reason copy];
    _userInfo = [userInfo copy];
    return self;
}
- (void)dealloc
{
    [_name release];
    [_reason release];
    [_userInfo release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSExceptionName)name { return _name; }
- (NSString *)reason { return _reason; }
- (NSDictionary *)userInfo { return _userInfo; }
- (NSString *)description { return _reason ?: _name; }
- (void)raise
{
    objc_exception_throw(self);
}
/* Ferry doesn't record where an exception was thrown from. */
- (NSArray *)callStackReturnAddresses { return @[]; }
- (NSArray *)callStackSymbols { return @[]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithName:[coder decodeObjectForKey:@"NSName"] reason:[coder decodeObjectForKey:@"NSReason"]
                     userInfo:[coder decodeObjectForKey:@"NSUserInfo"]];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"NSName"];
    [coder encodeObject:_reason forKey:@"NSReason"];
    [coder encodeObject:_userInfo forKey:@"NSUserInfo"];
}
@end

void FRaise(NSString *name, NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *reason = FFormat(format, ap);
    va_end(ap);
    [[NSException exceptionWithName:name reason:reason userInfo:nil] raise];
    abort();
}

/* ---- NSAutoreleasePool --------------------------------------------------------------- */

@implementation NSAutoreleasePool {
    void *_token;
}
+ (void)addObject:(id)obj { [obj autorelease]; }
- (instancetype)init
{
    _token = objc_autoreleasePoolPush();
    return self;
}
- (void)addObject:(id)obj { [obj autorelease]; }
- (id)retain
{
    FRaise(NSInvalidArgumentException, @"*** -[NSAutoreleasePool retain]: Cannot retain an autorelease pool");
}
- (id)autorelease
{
    FRaise(NSInvalidArgumentException, @"*** -[NSAutoreleasePool autorelease]: Cannot autorelease an autorelease pool");
}
- (void)drain
{
    objc_autoreleasePoolPop(_token);
    [self dealloc];
}
- (oneway void)release { [self drain]; }
@end

/* ---- functions --------------------------------------------------------------------- */

void NSLogv(NSString *format, va_list args)
{
    NSString *msg = FFormat(format, args);
    struct timeval tv;
    struct tm tm;
    char when[64];
    gettimeofday(&tv, NULL);
    time_t secs = tv.tv_sec;
    localtime_r(&secs, &tm);
    strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S", &tm);
    const char *text = [msg UTF8String];
    size_t n = strlen(text);
    fflush(stdout);
    fprintf(stderr, "%s.%03d %s[%d:%x] %s%s", when, (int)(tv.tv_usec / 1000),
            [[[NSProcessInfo processInfo] processName] UTF8String], (int)getpid(), (unsigned)getpid(), text,
            n && text[n - 1] == '\n' ? "" : "\n");
}

void NSLog(NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSLogv(format, ap);
    va_end(ap);
}

NSString *NSStringFromClass(Class cls) { return cls ? [NSString stringWithUTF8String:class_getName(cls)] : nil; }
Class NSClassFromString(NSString *name) { return name ? objc_getClass([name UTF8String]) : Nil; }
NSString *NSStringFromSelector(SEL sel) { return sel ? [NSString stringWithUTF8String:sel_getName(sel)] : nil; }
SEL NSSelectorFromString(NSString *name) { return name ? sel_registerName([name UTF8String]) : NULL; }
NSString *NSStringFromProtocol(Protocol *proto)
{
    return proto ? [NSString stringWithUTF8String:protocol_getName(proto)] : nil;
}
Protocol *NSProtocolFromString(NSString *name) { return name ? objc_getProtocol([name UTF8String]) : NULL; }
NSString *NSStringFromRange(NSRange range)
{
    return [NSString stringWithFormat:@"{%lu, %lu}", (unsigned long)range.location, (unsigned long)range.length];
}
NSRange NSRangeFromString(NSString *s)
{
    unsigned long a = 0, b = 0;
    sscanf([s UTF8String], "{%lu, %lu}", &a, &b);
    return NSMakeRange(a, b);
}

NSString *FHome(void)
{
    const char *h = getenv("HOME");
    if (!h || !*h) {
        struct passwd *pw = getpwuid(getuid());
        h = pw ? pw->pw_dir : "/";
    }
    return [NSString stringWithUTF8String:h];
}

NSString *FConfigHome(void)
{
    const char *x = getenv("XDG_CONFIG_HOME");
    if (x && x[0] == '/')
        return [NSString stringWithUTF8String:x];
    return [FHome() stringByAppendingPathComponent:@".config"];
}

/* A Mac user's Library, Application Support and Caches always exist, and
 * apps make their own folder in them without making the parent (OBS); so
 * here their counterparts are made when missing (freemac 1.263). */
static NSString *xdg_dir(const char *var, NSString *fallback)
{
    const char *x = getenv(var);
    NSString *d = x && x[0] == '/' ? [NSString stringWithUTF8String:x] : [FHome() stringByAppendingPathComponent:fallback];
    const char *p = [d fileSystemRepresentation];
    if (access(p, F_OK) != 0) {
        char buf[4096];
        snprintf(buf, sizeof buf, "%s", p);
        for (char *c = buf + 1; *c; c++)
            if (*c == '/') {
                *c = 0;
                mkdir(buf, 0700);
                *c = '/';
            }
        mkdir(buf, 0700);
    }
    return d;
}

NSString *NSHomeDirectory(void) { return FHome(); }
NSString *NSHomeDirectoryForUser(NSString *name)
{
    /* this user's is the one NSHomeDirectory gives, which follows $HOME */
    if (!name || [name isEqualToString:NSUserName()])
        return NSHomeDirectory();
    struct passwd *pw = getpwnam([name UTF8String]);
    return pw && pw->pw_dir ? [NSString stringWithUTF8String:pw->pw_dir] : nil;
}
NSString *NSTemporaryDirectory(void)
{
    const char *t = getenv("TMPDIR");
    NSString *s = [NSString stringWithUTF8String:t && *t ? t : "/tmp"];
    return [s hasSuffix:@"/"] ? s : [s stringByAppendingString:@"/"];
}
NSString *NSUserName(void)
{
    struct passwd *pw = getpwuid(getuid());
    return [NSString stringWithUTF8String:pw ? pw->pw_name : (getenv("USER") ?: "user")];
}
NSString *NSFullUserName(void)
{
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_gecos && *pw->pw_gecos) {
        NSString *g = [NSString stringWithUTF8String:pw->pw_gecos];
        return [[g componentsSeparatedByString:@","] objectAtIndex:0];
    }
    return NSUserName();
}

/* A person's own folders, as the desktop names them in user-dirs.dirs
 * (XDG_VIDEOS_DIR="$HOME/Videos", and in other languages other names),
 * else the usual English name. A Mac always has its Movies, Music and
 * Pictures folders, and apps such as HandBrake take a missing one as a
 * bad place to save to, so a missing folder is made (freemac 1.264). */
static NSString *user_dir(const char *key, NSString *fallback)
{
    NSString *home = FHome(), *found = nil;
    const char *cfg = getenv("XDG_CONFIG_HOME");
    NSString *file = cfg && cfg[0] == '/' ? [NSString stringWithUTF8String:cfg]
                                          : [home stringByAppendingPathComponent:@".config"];
    FILE *f = fopen([[file stringByAppendingPathComponent:@"user-dirs.dirs"] fileSystemRepresentation], "r");
    if (f) {
        char line[1024];
        size_t klen = strlen(key);
        while (fgets(line, sizeof line, f)) {
            if (strncmp(line, key, klen) || line[klen] != '=')
                continue;
            char *v = line + klen + 1, *end;
            if (*v == '"')
                v++;
            if ((end = strchr(v, '"')) || (end = strchr(v, '\n')))
                *end = 0;
            if (!strncmp(v, "$HOME", 5))
                found = [home stringByAppendingString:[NSString stringWithUTF8String:v + 5]];
            else if (v[0] == '/')
                found = [NSString stringWithUTF8String:v];
            break;
        }
        fclose(f);
    }
    /* "$HOME/" alone means the desktop turned the folder off: the home folder */
    if (found && [[found stringByStandardizingPath] isEqualToString:[home stringByStandardizingPath]])
        found = nil;
    NSString *d = found ?: [home stringByAppendingPathComponent:fallback];
    if (access([d fileSystemRepresentation], F_OK) != 0)
        mkdir([d fileSystemRepresentation], 0755);
    return d;
}

/* Where a Mac app's own folders are on freemac, in the user domain. */
NSString *FUserFolder(NSSearchPathDirectory dir)
{
    switch (dir) {
    case NSApplicationDirectory: return [FHome() stringByAppendingPathComponent:@"Applications"];
    case NSLibraryDirectory:
    case NSApplicationSupportDirectory: return xdg_dir("XDG_DATA_HOME", @".local/share");
    case NSCachesDirectory: return xdg_dir("XDG_CACHE_HOME", @".cache");
    case NSDocumentDirectory: return user_dir("XDG_DOCUMENTS_DIR", @"Documents");
    case NSDesktopDirectory: return user_dir("XDG_DESKTOP_DIR", @"Desktop");
    case NSDownloadsDirectory: return user_dir("XDG_DOWNLOAD_DIR", @"Downloads");
    case NSMoviesDirectory: return user_dir("XDG_VIDEOS_DIR", @"Videos");
    case NSMusicDirectory: return user_dir("XDG_MUSIC_DIR", @"Music");
    case NSPicturesDirectory: return user_dir("XDG_PICTURES_DIR", @"Pictures");
    case NSUserDirectory: return [FHome() stringByDeletingLastPathComponent];
    default: return nil; /* a Mac folder with no counterpart here */
    }
}

/* The computer's own folders, a Mac's local and system domains. freemac puts
 * apps for everyone in /Applications and their files in /usr/local/share, as
 * the shell's installer does; the system's own data is /usr/share. A Mac
 * answers with a folder whether or not it exists (freemac 1.239). */
static NSString *local_folder(NSSearchPathDirectory dir)
{
    switch (dir) {
    case NSApplicationDirectory: return @"/Applications";
    case NSLibraryDirectory:
    case NSApplicationSupportDirectory: return @"/usr/local/share";
    case NSCachesDirectory: return @"/var/cache";
    default: return nil;
    }
}
static NSString *system_folder(NSSearchPathDirectory dir)
{
    switch (dir) {
    case NSLibraryDirectory:
    case NSApplicationSupportDirectory: return @"/usr/share";
    default: return nil;
    }
}

NSArray *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory dir, NSSearchPathDomainMask mask, BOOL expandTilde)
{
    /* in a Mac's order: user, local, network (none here), system */
    NSMutableArray *a = [NSMutableArray array];
    NSString *p = (mask & NSUserDomainMask) ? FUserFolder(dir) : nil;
    if (p)
        [a addObject:expandTilde ? p : [p stringByAbbreviatingWithTildeInPath]];
    if ((mask & NSLocalDomainMask) && (p = local_folder(dir)) && ![a containsObject:p])
        [a addObject:p];
    if ((mask & NSSystemDomainMask) && (p = system_folder(dir)) && ![a containsObject:p])
        [a addObject:p];
    return a;
}
