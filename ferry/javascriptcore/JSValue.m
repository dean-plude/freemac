/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's JavaScriptCore: the Objective-C API (freemac 1.222, Ferry
 * 0.46.0), written from its public documentation on top of the C API
 * (JSCForward.m).
 *
 * A JSContext owns one global context; a JSValue keeps its value protected
 * from the collector and its context alive. Values cross between the two
 * languages as the documentation's table gives: nil and undefined, NSNull
 * and null, NSString and strings, NSNumber and numbers and booleans, NSDate
 * and Date, NSArray and arrays, NSDictionary and other objects, a block and
 * a function that calls it. Any other object reaches JavaScript wrapped,
 * showing the methods and properties of each protocol its class adopts
 * that adopts JSExport. A call from JavaScript into a block or an exported
 * method converts each argument to the type its signature gives (the
 * block's own signature, the protocol's extended method types) and the
 * result back, through NSInvocation.
 *
 * Unlike Apple's, an object wrapped for JavaScript stays alive as long as
 * its context does, and a context as long as any of its values does; so a
 * JSValue kept by an object that a context's script can reach keeps both,
 * and JSManagedValue holds its value strongly. Built without ARC. */
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <string.h>

const char *_Block_signature(void *block);
const char *_protocol_getMethodTypeEncoding(Protocol *p, SEL sel, BOOL required, BOOL instance);

@interface NSInvocation (FerryFunction)
- (void)_invokeFunction:(void *)function;
@end

NSString *const JSPropertyDescriptorWritableKey = @"writable";
NSString *const JSPropertyDescriptorEnumerableKey = @"enumerable";
NSString *const JSPropertyDescriptorConfigurableKey = @"configurable";
NSString *const JSPropertyDescriptorValueKey = @"value";
NSString *const JSPropertyDescriptorGetKey = @"get";
NSString *const JSPropertyDescriptorSetKey = @"set";

@interface JSVirtualMachine () {
@public
    JSContextGroupRef _group;
}
@end

@interface JSContext () {
@public
    JSGlobalContextRef _ctx;
    JSVirtualMachine *_vm;
    JSValue *_exception;
    void (^_handler)(JSContext *, JSValue *);
    NSString *_name;
    NSMutableDictionary *_wrappers; /* object's address -> its wrapper, protected */
}
- (void)_notifyException:(JSValueRef)exception;
@end

@interface JSValue () {
@public
    JSValueRef _ref;
    JSContext *_context;
}
@end

/* ---- strings -------------------------------------------------------------------------- */

static JSStringRef JSCString(NSString *s) { return JSStringCreateWithCFString((CFStringRef)(s ? s : @"")); }

static NSString *NSStringFromJS(JSStringRef s)
{
    if (!s)
        return nil;
    NSString *r = (NSString *)JSStringCopyCFString(kCFAllocatorDefault, s);
    return [r autorelease];
}

static NSString *KeyString(id key)
{
    return [key isKindOfClass:[NSString class]] ? key : [key description];
}

/* ---- the contexts there are, by global context, and what a callback runs in ------------- */

static pthread_mutex_t registry_lock = PTHREAD_MUTEX_INITIALIZER;
static struct reg {
    JSGlobalContextRef ctx;
    JSContext *context;
    struct reg *next;
} *registry;

static JSContext *ContextFor(JSContextRef ctx)
{
    JSGlobalContextRef g = JSContextGetGlobalContext(ctx);
    JSContext *found = nil;
    pthread_mutex_lock(&registry_lock);
    for (struct reg *r = registry; r; r = r->next)
        if (r->ctx == g) {
            found = r->context;
            break;
        }
    pthread_mutex_unlock(&registry_lock);
    return found;
}

struct current {
    JSContext *context;
    JSObjectRef callee, thisObject;
    size_t argc;
    const JSValueRef *argv;
    struct current *outer;
};
static __thread struct current *current;

/* Objects whose wrapper the collector finalized, released outside the collector. */
static pthread_mutex_t pending_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray *pending;

static void ReleaseLater(id object)
{
    if (!object)
        return;
    pthread_mutex_lock(&pending_lock);
    if (!pending)
        pending = [[NSMutableArray alloc] init];
    [pending addObject:object];
    pthread_mutex_unlock(&pending_lock);
    [object release];
}

static void DrainPending(void)
{
    pthread_mutex_lock(&pending_lock);
    NSMutableArray *list = pending;
    pending = nil;
    pthread_mutex_unlock(&pending_lock);
    [list release];
}

/* ---- JavaScript to Objective-C ---------------------------------------------------------- */

static JSClassRef ObjectClass(void);
static JSClassRef BlockClass(void);
static JSClassRef MethodClass(void);

static double NumberProperty(JSContextRef ctx, JSValueRef v, const char *name)
{
    if (!JSValueIsObject(ctx, v))
        return 0;
    JSStringRef s = JSStringCreateWithUTF8CString(name);
    JSValueRef p = JSObjectGetProperty(ctx, (JSObjectRef)v, s, NULL);
    JSStringRelease(s);
    return p ? JSValueToNumber(ctx, p, NULL) : 0;
}

static id ObjectFromJS(JSContext *c, JSValueRef v, int depth);

static NSArray *ArrayFromJS(JSContext *c, JSValueRef v, int depth)
{
    JSContextRef ctx = c->_ctx;
    JSObjectRef o = (JSObjectRef)v;
    unsigned n = (unsigned)NumberProperty(ctx, v, "length");
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
    for (unsigned i = 0; i < n; i++) {
        id e = ObjectFromJS(c, JSObjectGetPropertyAtIndex(ctx, o, i, NULL), depth + 1);
        [a addObject:e ? e : [NSNull null]];
    }
    return a;
}

static NSDictionary *DictionaryFromJS(JSContext *c, JSValueRef v, int depth)
{
    JSContextRef ctx = c->_ctx;
    JSObjectRef o = (JSObjectRef)v;
    JSPropertyNameArrayRef names = JSObjectCopyPropertyNames(ctx, o);
    size_t n = JSPropertyNameArrayGetCount(names);
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:n];
    for (size_t i = 0; i < n; i++) {
        JSStringRef name = JSPropertyNameArrayGetNameAtIndex(names, i);
        id e = ObjectFromJS(c, JSObjectGetProperty(ctx, o, name, NULL), depth + 1);
        if (e)
            d[NSStringFromJS(name)] = e;
    }
    JSPropertyNameArrayRelease(names);
    return d;
}

static id ObjectFromJS(JSContext *c, JSValueRef v, int depth)
{
    JSContextRef ctx = c->_ctx;
    if (!v || depth > 64)
        return nil;
    switch (JSValueGetType(ctx, v)) {
    case kJSTypeUndefined:
        return nil;
    case kJSTypeNull:
        return [NSNull null];
    case kJSTypeBoolean:
        return JSValueToBoolean(ctx, v) ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    case kJSTypeNumber:
        return [NSNumber numberWithDouble:JSValueToNumber(ctx, v, NULL)];
    case kJSTypeString: {
        JSStringRef s = JSValueToStringCopy(ctx, v, NULL);
        NSString *r = NSStringFromJS(s);
        JSStringRelease(s);
        return r;
    }
    case kJSTypeObject:
        break;
    default:
        return [JSValue valueWithJSValueRef:v inContext:c];
    }
    if (JSValueIsObjectOfClass(ctx, v, ObjectClass()) || JSValueIsObjectOfClass(ctx, v, BlockClass()))
        return (id)JSObjectGetPrivate((JSObjectRef)v);
    if (JSValueIsDate(ctx, v))
        return [NSDate dateWithTimeIntervalSince1970:JSValueToNumber(ctx, v, NULL) / 1000.0];
    if (JSValueIsArray(ctx, v))
        return ArrayFromJS(c, v, depth);
    return DictionaryFromJS(c, v, depth);
}

/* ---- Objective-C to JavaScript ---------------------------------------------------------- */

static BOOL IsBoolean(NSNumber *n) { return n == (id)kCFBooleanTrue || n == (id)kCFBooleanFalse; }

static JSValueRef WrapperFor(JSContext *c, id object);

static JSValueRef ValueFromObject(JSContext *c, id object)
{
    JSContextRef ctx = c->_ctx;
    if (!object)
        return JSValueMakeUndefined(ctx);
    if ([object isKindOfClass:[JSValue class]])
        return ((JSValue *)object)->_ref;
    if (object == [NSNull null])
        return JSValueMakeNull(ctx);
    if ([object isKindOfClass:[NSString class]]) {
        JSStringRef s = JSCString(object);
        JSValueRef v = JSValueMakeString(ctx, s);
        JSStringRelease(s);
        return v;
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        if (IsBoolean(object))
            return JSValueMakeBoolean(ctx, [object boolValue]);
        return JSValueMakeNumber(ctx, [object doubleValue]);
    }
    if ([object isKindOfClass:[NSDate class]]) {
        JSValueRef ms = JSValueMakeNumber(ctx, [object timeIntervalSince1970] * 1000.0);
        return JSObjectMakeDate(ctx, 1, &ms, NULL);
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *a = object;
        NSUInteger n = a.count;
        JSValueRef *items = n ? malloc(n * sizeof *items) : NULL;
        for (NSUInteger i = 0; i < n; i++) {
            items[i] = ValueFromObject(c, a[i]);
            JSValueProtect(ctx, items[i]);
        }
        JSObjectRef r = JSObjectMakeArray(ctx, n, items, NULL);
        for (NSUInteger i = 0; i < n; i++)
            JSValueUnprotect(ctx, items[i]);
        free(items);
        return r;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        JSObjectRef o = JSObjectMake(ctx, NULL, NULL);
        for (id key in (NSDictionary *)object) {
            JSStringRef s = JSCString(KeyString(key));
            JSObjectSetProperty(ctx, o, s, ValueFromObject(c, ((NSDictionary *)object)[key]),
                                kJSPropertyAttributeNone, NULL);
            JSStringRelease(s);
        }
        return o;
    }
    if ([object isKindOfClass:NSClassFromString(@"NSBlock")])
        return JSObjectMake(ctx, BlockClass(), [object copy]);
    return WrapperFor(c, object);
}

static JSValueRef WrapperFor(JSContext *c, id object)
{
    NSValue *key = [NSValue valueWithPointer:object];
    NSValue *have = c->_wrappers[key];
    if (have)
        return (JSValueRef)[have pointerValue];
    JSObjectRef w = JSObjectMake(c->_ctx, ObjectClass(), [object retain]);
    JSValueProtect(c->_ctx, w);
    c->_wrappers[key] = [NSValue valueWithPointer:w];
    return w;
}

/* ---- calling Objective-C from JavaScript ------------------------------------------------ */

static const char *SkipQualifiers(const char *t)
{
    while (*t && strchr("rnNoORV", *t))
        t++;
    return t;
}

static BOOL StructNamed(const char *t, const char *name)
{
    size_t n = strlen(name);
    return t[0] == '{' && !strncmp(t + 1, name, n) && t[1 + n] == '=';
}

/* The class a '@"Name"' type names, or nil. */
static Class ClassOfType(const char *t)
{
    if (t[0] != '@' || t[1] != '"')
        return Nil;
    const char *end = strchr(t + 2, '"');
    if (!end)
        return Nil;
    char name[256];
    size_t n = (size_t)(end - (t + 2));
    if (n >= sizeof name)
        return Nil;
    memcpy(name, t + 2, n);
    name[n] = 0;
    return objc_getClass(name);
}

static void SetArgument(NSInvocation *inv, NSInteger index, const char *type, JSValueRef v, JSContext *c)
{
    JSContextRef ctx = c->_ctx;
    const char *t = SkipQualifiers(type);
    double d = v ? JSValueToNumber(ctx, v, NULL) : 0;
    if (d != d)
        d = 0;
    switch (*t) {
#define NUM(code, ctype)                                                                                    \
    case code: {                                                                                            \
        ctype x = (ctype)d;                                                                                 \
        [inv setArgument:&x atIndex:index];                                                                 \
        return;                                                                                             \
    }
        NUM('C', unsigned char)
        NUM('s', short)
        NUM('S', unsigned short)
        NUM('i', int)
        NUM('I', unsigned int)
        NUM('l', long)
        NUM('L', unsigned long)
        NUM('q', long long)
        NUM('Q', unsigned long long)
        NUM('f', float)
        NUM('d', double)
#undef NUM
    case 'c':
    case 'B': {
        char x = v && JSValueIsBoolean(ctx, v) ? (char)JSValueToBoolean(ctx, v) : (char)(long long)d;
        if (*t == 'B')
            x = x != 0;
        [inv setArgument:&x atIndex:index];
        return;
    }
    case '*': {
        JSValue *jv = [JSValue valueWithJSValueRef:v inContext:c];
        const char *s = [[jv toString] UTF8String];
        [inv setArgument:&s atIndex:index];
        return;
    }
    case '@': {
        id o = nil;
        if (v && t[1] != '?') {
            JSValue *jv = [JSValue valueWithJSValueRef:v inContext:c];
            Class want = ClassOfType(t);
            if (want && [want isSubclassOfClass:[JSValue class]])
                o = jv;
            else if (want && [want isSubclassOfClass:[NSString class]])
                o = jv.isUndefined || jv.isNull ? nil : [jv toString];
            else if (want && [want isSubclassOfClass:[NSNumber class]])
                o = [jv toNumber];
            else if (want && [want isSubclassOfClass:[NSDate class]])
                o = [jv toDate];
            else if (want && [want isSubclassOfClass:[NSArray class]])
                o = [jv toArray];
            else if (want && [want isSubclassOfClass:[NSDictionary class]])
                o = [jv toDictionary];
            else
                o = [jv toObject];
        }
        [inv setArgument:&o atIndex:index];
        return;
    }
    case '{': {
        JSValue *jv = [JSValue valueWithJSValueRef:v inContext:c];
        if (StructNamed(t, "CGRect") || StructNamed(t, "NSRect") || StructNamed(t, "_NSRect")) {
            CGRect r = [jv toRect];
            [inv setArgument:&r atIndex:index];
        } else if (StructNamed(t, "CGPoint") || StructNamed(t, "NSPoint") || StructNamed(t, "_NSPoint")) {
            CGPoint p = [jv toPoint];
            [inv setArgument:&p atIndex:index];
        } else if (StructNamed(t, "CGSize") || StructNamed(t, "NSSize") || StructNamed(t, "_NSSize")) {
            CGSize s = [jv toSize];
            [inv setArgument:&s atIndex:index];
        } else if (StructNamed(t, "_NSRange") || StructNamed(t, "NSRange")) {
            NSRange r = [jv toRange];
            [inv setArgument:&r atIndex:index];
        }
        return; /* any other structure stays zero */
    }
    default:
        return; /* pointers, classes and selectors stay zero */
    }
}

static JSValueRef ResultValue(NSInvocation *inv, JSContext *c)
{
    JSContextRef ctx = c->_ctx;
    NSMethodSignature *sig = inv.methodSignature;
    const char *t = SkipQualifiers(sig.methodReturnType);
    if (*t == 'v' || !sig.methodReturnLength)
        return JSValueMakeUndefined(ctx);
    char buf[sig.methodReturnLength < 16 ? 16 : sig.methodReturnLength];
    memset(buf, 0, sizeof buf);
    [inv getReturnValue:buf];
    switch (*t) {
#define NUM(code, ctype)                                                                                    \
    case code: {                                                                                            \
        ctype x;                                                                                            \
        memcpy(&x, buf, sizeof x);                                                                          \
        return JSValueMakeNumber(ctx, (double)x);                                                           \
    }
        NUM('C', unsigned char)
        NUM('s', short)
        NUM('S', unsigned short)
        NUM('i', int)
        NUM('I', unsigned int)
        NUM('l', long)
        NUM('L', unsigned long)
        NUM('q', long long)
        NUM('Q', unsigned long long)
        NUM('f', float)
        NUM('d', double)
#undef NUM
    case 'c':
    case 'B':
        return JSValueMakeBoolean(ctx, buf[0] != 0);
    case '*': {
        const char *s;
        memcpy(&s, buf, sizeof s);
        return s ? ValueFromObject(c, [NSString stringWithUTF8String:s]) : JSValueMakeNull(ctx);
    }
    case '@': {
        id o;
        memcpy(&o, buf, sizeof o);
        return ValueFromObject(c, o);
    }
    case '{':
        if (StructNamed(t, "CGRect") || StructNamed(t, "NSRect") || StructNamed(t, "_NSRect")) {
            CGRect r;
            memcpy(&r, buf, sizeof r);
            return [JSValue valueWithRect:r inContext:c]->_ref;
        }
        if (StructNamed(t, "CGPoint") || StructNamed(t, "NSPoint") || StructNamed(t, "_NSPoint")) {
            CGPoint p;
            memcpy(&p, buf, sizeof p);
            return [JSValue valueWithPoint:p inContext:c]->_ref;
        }
        if (StructNamed(t, "CGSize") || StructNamed(t, "NSSize") || StructNamed(t, "_NSSize")) {
            CGSize s;
            memcpy(&s, buf, sizeof s);
            return [JSValue valueWithSize:s inContext:c]->_ref;
        }
        if (StructNamed(t, "_NSRange") || StructNamed(t, "NSRange")) {
            NSRange r;
            memcpy(&r, buf, sizeof r);
            return [JSValue valueWithRange:r inContext:c]->_ref;
        }
        return JSValueMakeUndefined(ctx);
    default:
        return JSValueMakeUndefined(ctx);
    }
}

static JSValueRef ErrorValue(JSContextRef ctx, NSString *message)
{
    JSStringRef s = JSCString(message);
    JSValueRef m = JSValueMakeString(ctx, s);
    JSStringRelease(s);
    return JSObjectMakeError(ctx, 1, &m, NULL);
}

/* Runs call with the context's current callee, this and arguments set, an
 * exception the call stores in context.exception thrown into the script,
 * and an Objective-C exception turned into a JavaScript Error. */
static JSValueRef CallOut(JSContextRef ctx, JSObjectRef callee, JSObjectRef thisObject, size_t argc,
                          const JSValueRef argv[], JSValueRef *exception, JSValueRef (^call)(JSContext *c))
{
    DrainPending();
    JSContext *c = ContextFor(ctx);
    if (!c)
        return JSValueMakeUndefined(ctx);
    struct current frame = {c, callee, thisObject, argc, argv, current};
    current = &frame;
    JSValue *before = [c->_exception retain];
    [c->_exception release];
    c->_exception = nil;
    JSValueRef result = NULL;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    @try {
        result = call(c);
        if (result)
            JSValueProtect(ctx, result);
    } @catch (NSException *e) {
        if (exception)
            *exception = ErrorValue(ctx, [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
    [pool drain];
    if (c->_exception && exception)
        *exception = c->_exception->_ref;
    [c->_exception release];
    c->_exception = before;
    current = frame.outer;
    if (!result)
        return JSValueMakeUndefined(ctx);
    JSValueUnprotect(ctx, result);
    return result;
}

static JSValueRef BlockCall(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc,
                            const JSValueRef argv[], JSValueRef *exception)
{
    id block = (id)JSObjectGetPrivate(function);
    return CallOut(ctx, function, thisObject, argc, argv, exception, ^JSValueRef(JSContext *c) {
        const char *types = _Block_signature(block);
        if (!types)
            return JSValueMakeUndefined(ctx);
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:types];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        id self_ = block;
        [inv setArgument:&self_ atIndex:0];
        for (NSUInteger i = 1; i < sig.numberOfArguments; i++)
            SetArgument(inv, (NSInteger)i, [sig getArgumentTypeAtIndex:i], i - 1 < argc ? argv[i - 1] : NULL, c);
        struct {
            void *isa;
            int flags, reserved;
            void *invoke;
        } *layout = (void *)block;
        [inv _invokeFunction:layout->invoke];
        return ResultValue(inv, c);
    });
}

static void ReleasePrivate(JSObjectRef object) { ReleaseLater((id)JSObjectGetPrivate(object)); }

/* ---- what JavaScript sees of an exported object ----------------------------------------- */

@interface JSCMember : NSObject {
@public
    SEL sel;             /* a method, or a property's getter */
    SEL setter;          /* a property's setter, or NULL */
    BOOL property;
    char *types, *setterTypes;
}
@end
@implementation JSCMember
- (void)dealloc
{
    free(types);
    free(setterTypes);
    [super dealloc];
}
@end

static NSString *ScriptName(SEL sel)
{
    NSArray *parts = [NSStringFromSelector(sel) componentsSeparatedByString:@":"];
    NSMutableString *name = [NSMutableString stringWithString:parts[0]];
    for (NSUInteger i = 1; i < parts.count; i++) {
        NSString *p = parts[i];
        if (p.length)
            [name appendFormat:@"%@%@", [[p substringToIndex:1] uppercaseString], [p substringFromIndex:1]];
    }
    return name;
}

static char *TypesFor(Protocol *p, SEL sel, BOOL required, BOOL instance, Class cls)
{
    const char *t = _protocol_getMethodTypeEncoding(p, sel, required, instance);
    if (!t) {
        Method m = instance ? class_getInstanceMethod(cls, sel) : class_getClassMethod(cls, sel);
        t = m ? method_getTypeEncoding(m) : NULL;
    }
    return t ? strdup(t) : NULL;
}

static void AddProtocol(NSMutableDictionary *members, Protocol *p, BOOL instance, Class cls, NSMutableSet *seen)
{
    NSString *pname = p ? @(protocol_getName(p)) : nil;
    if (!p || p == @protocol(JSExport) || [seen containsObject:pname])
        return;
    [seen addObject:pname];
    NSMutableDictionary *renames = [NSMutableDictionary dictionary];
    for (int required = 1; required >= 0; required--) {
        unsigned n = 0;
        struct objc_method_description *list = protocol_copyMethodDescriptionList(p, required, instance, &n);
        for (unsigned i = 0; i < n; i++) {
            NSString *s = NSStringFromSelector(list[i].name);
            NSRange r = [s rangeOfString:@"__JS_EXPORT_AS__"];
            if (r.location != NSNotFound) {
                NSString *as = [s substringFromIndex:NSMaxRange(r)];
                as = [as substringToIndex:as.length - 1]; /* the trailing colon */
                renames[[s substringToIndex:r.location]] = as;
                continue;
            }
            if (!members[s]) {
                JSCMember *m = [[JSCMember alloc] init];
                m->sel = list[i].name;
                m->types = TypesFor(p, list[i].name, required, instance, cls);
                members[s] = m;
                [m release];
            }
        }
        free(list);
    }
    /* key the methods by their JavaScript names */
    for (NSString *s in [members allKeys]) {
        JSCMember *m = members[s];
        if (![m isKindOfClass:[JSCMember class]] || m->property || ![s isEqualToString:NSStringFromSelector(m->sel)])
            continue;
        NSString *name = renames[s] ? renames[s] : ScriptName(m->sel);
        [m retain];
        [members removeObjectForKey:s];
        if (!members[name])
            members[name] = m;
        [m release];
    }
    if (instance) {
        unsigned n = 0;
        objc_property_t *props = protocol_copyPropertyList(p, &n);
        for (unsigned i = 0; i < n; i++) {
            NSString *name = @(property_getName(props[i]));
            NSString *getter = name, *setter = nil;
            BOOL readonly = NO;
            for (NSString *a in [@(property_getAttributes(props[i])) componentsSeparatedByString:@","]) {
                if ([a hasPrefix:@"G"])
                    getter = [a substringFromIndex:1];
                else if ([a hasPrefix:@"S"])
                    setter = [a substringFromIndex:1];
                else if ([a isEqualToString:@"R"])
                    readonly = YES;
            }
            if (!setter && !readonly)
                setter = [NSString stringWithFormat:@"set%@%@:", [[name substringToIndex:1] uppercaseString],
                                                    [name substringFromIndex:1]];
            JSCMember *m = [[JSCMember alloc] init];
            m->property = YES;
            m->sel = NSSelectorFromString(getter);
            m->types = TypesFor(p, m->sel, YES, YES, cls);
            if (!m->types)
                m->types = TypesFor(p, m->sel, NO, YES, cls);
            if (setter) {
                m->setter = NSSelectorFromString(setter);
                m->setterTypes = TypesFor(p, m->setter, YES, YES, cls);
                if (!m->setterTypes)
                    m->setterTypes = TypesFor(p, m->setter, NO, YES, cls);
            }
            members[name] = m; /* a property's name wins over its getter's */
            [m release];
        }
        free(props);
    }
    unsigned n = 0;
    Protocol *__unsafe_unretained *adopted = protocol_copyProtocolList(p, &n);
    for (unsigned i = 0; i < n; i++)
        if (protocol_conformsToProtocol(adopted[i], @protocol(JSExport)))
            AddProtocol(members, adopted[i], instance, cls, seen);
    free(adopted);
}

/* What JavaScript sees of an object of this class (a class object's class
 * methods for a metaclass), by JavaScript name. */
static NSDictionary *MembersOf(Class cls)
{
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static NSMutableDictionary *cache;
    pthread_mutex_lock(&lock);
    if (!cache)
        cache = [[NSMutableDictionary alloc] init];
    NSValue *key = [NSValue valueWithPointer:cls];
    NSDictionary *have = cache[key];
    if (!have) {
        BOOL instance = !class_isMetaClass(cls);
        Class base = instance ? cls : (Class)objc_getClass(class_getName(cls));
        NSMutableDictionary *members = [NSMutableDictionary dictionary];
        NSMutableSet *seen = [NSMutableSet set];
        for (Class k = base; k; k = class_getSuperclass(k)) {
            unsigned n = 0;
            Protocol *__unsafe_unretained *list = class_copyProtocolList(k, &n);
            for (unsigned i = 0; i < n; i++)
                if (protocol_conformsToProtocol(list[i], @protocol(JSExport)))
                    AddProtocol(members, list[i], instance, base, seen);
            free(list);
        }
        have = members;
        cache[key] = have;
    }
    pthread_mutex_unlock(&lock);
    return have;
}

struct JSCBound {
    id object;
    SEL sel;
    char *types;
};

static JSValueRef Invoke(JSContext *c, id object, SEL sel, const char *types, size_t argc, const JSValueRef argv[])
{
    if (!types || ![object respondsToSelector:sel])
        return JSValueMakeUndefined(c->_ctx);
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:types];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:object];
    [inv setSelector:sel];
    for (NSUInteger i = 2; i < sig.numberOfArguments; i++)
        SetArgument(inv, (NSInteger)i, [sig getArgumentTypeAtIndex:i], i - 2 < argc ? argv[i - 2] : NULL, c);
    [inv invoke];
    return ResultValue(inv, c);
}

static JSValueRef MethodCall(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc,
                             const JSValueRef argv[], JSValueRef *exception)
{
    struct JSCBound *b = JSObjectGetPrivate(function);
    return CallOut(ctx, function, thisObject, argc, argv, exception, ^JSValueRef(JSContext *c) {
        return Invoke(c, b->object, b->sel, b->types, argc, argv);
    });
}

static void MethodFinalize(JSObjectRef object)
{
    struct JSCBound *b = JSObjectGetPrivate(object);
    if (!b)
        return;
    ReleaseLater(b->object);
    free(b->types);
    free(b);
}

static JSCMember *MemberNamed(JSObjectRef object, JSStringRef name)
{
    id target = (id)JSObjectGetPrivate(object);
    if (!target)
        return nil;
    return MembersOf(object_getClass(target))[NSStringFromJS(name)];
}

static JSValueRef ObjectGet(JSContextRef ctx, JSObjectRef object, JSStringRef name, JSValueRef *exception)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    JSCMember *m = MemberNamed(object, name);
    id target = (id)JSObjectGetPrivate(object);
    JSValueRef r = NULL;
    if (m && m->property) {
        r = CallOut(ctx, object, object, 0, NULL, exception, ^JSValueRef(JSContext *c) {
            return Invoke(c, target, m->sel, m->types, 0, NULL);
        });
    } else if (m) {
        struct JSCBound *b = calloc(1, sizeof *b);
        b->object = [target retain];
        b->sel = m->sel;
        b->types = m->types ? strdup(m->types) : NULL;
        r = JSObjectMake(ctx, MethodClass(), b);
    }
    [pool drain];
    return r;
}

static bool ObjectSet(JSContextRef ctx, JSObjectRef object, JSStringRef name, JSValueRef value,
                      JSValueRef *exception)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    JSCMember *m = MemberNamed(object, name);
    id target = (id)JSObjectGetPrivate(object);
    bool handled = false;
    if (m && m->property && m->setter) {
        CallOut(ctx, object, object, 1, &value, exception, ^JSValueRef(JSContext *c) {
            return Invoke(c, target, m->setter, m->setterTypes, 1, &value);
        });
        handled = true;
    }
    [pool drain];
    return handled;
}

static JSClassRef MakeClass(const char *name, JSObjectGetPropertyCallback get, JSObjectSetPropertyCallback set,
                            JSObjectCallAsFunctionCallback call, JSObjectFinalizeCallback finalize)
{
    JSClassDefinition d = kJSClassDefinitionEmpty;
    d.className = name;
    d.getProperty = get;
    d.setProperty = set;
    d.callAsFunction = call;
    d.finalize = finalize;
    return JSClassCreate(&d);
}

static JSClassRef ObjectClass(void)
{
    static JSClassRef c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = MakeClass("ObjCObject", ObjectGet, ObjectSet, NULL, ReleasePrivate);
    });
    return c;
}

static JSClassRef BlockClass(void)
{
    static JSClassRef c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = MakeClass("ObjCBlock", NULL, NULL, BlockCall, ReleasePrivate);
    });
    return c;
}

static JSClassRef MethodClass(void)
{
    static JSClassRef c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = MakeClass("ObjCMethod", NULL, NULL, MethodCall, MethodFinalize);
    });
    return c;
}

/* ---- JSVirtualMachine ------------------------------------------------------------------- */

@implementation JSVirtualMachine
- (instancetype)init
{
    if ((self = [super init]))
        _group = JSContextGroupCreate();
    return self;
}
- (void)dealloc
{
    if (_group)
        JSContextGroupRelease(_group);
    [super dealloc];
}
- (void)addManagedReference:(id)object withOwner:(id)owner
{
}
- (void)removeManagedReference:(id)object withOwner:(id)owner
{
}
@end

/* ---- JSContext -------------------------------------------------------------------------- */

@implementation JSContext

- (instancetype)init
{
    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    self = [self initWithVirtualMachine:vm];
    [vm release];
    return self;
}

- (instancetype)_initWithGlobalContext:(JSGlobalContextRef)ctx virtualMachine:(JSVirtualMachine *)vm
{
    if (!(self = [super init]))
        return nil;
    _ctx = ctx;
    _vm = [vm retain];
    _wrappers = [[NSMutableDictionary alloc] init];
    struct reg *r = malloc(sizeof *r);
    r->ctx = ctx;
    r->context = self;
    pthread_mutex_lock(&registry_lock);
    r->next = registry;
    registry = r;
    pthread_mutex_unlock(&registry_lock);
    return self;
}

- (instancetype)initWithVirtualMachine:(JSVirtualMachine *)virtualMachine
{
    JSGlobalContextRef ctx = JSGlobalContextCreateInGroup(virtualMachine->_group, NULL);
    return [self _initWithGlobalContext:ctx virtualMachine:virtualMachine];
}

+ (JSContext *)contextWithJSGlobalContextRef:(JSGlobalContextRef)jsGlobalContextRef
{
    JSContext *have = ContextFor(jsGlobalContextRef);
    if (have)
        return have;
    JSVirtualMachine *vm = [[[JSVirtualMachine alloc] init] autorelease];
    return [[[self alloc] _initWithGlobalContext:JSGlobalContextRetain(jsGlobalContextRef)
                                  virtualMachine:vm] autorelease];
}

- (void)dealloc
{
    pthread_mutex_lock(&registry_lock);
    for (struct reg **p = &registry; *p; p = &(*p)->next)
        if ((*p)->context == self) {
            struct reg *gone = *p;
            *p = gone->next;
            free(gone);
            break;
        }
    pthread_mutex_unlock(&registry_lock);
    for (NSValue *w in [_wrappers allValues])
        JSValueUnprotect(_ctx, (JSValueRef)[w pointerValue]);
    [_wrappers release];
    [_exception release];
    [_handler release];
    [_name release];
    JSGlobalContextRelease(_ctx);
    [_vm release];
    DrainPending();
    [super dealloc];
}

- (JSGlobalContextRef)JSGlobalContextRef { return _ctx; }
- (JSVirtualMachine *)virtualMachine { return _vm; }

- (JSValue *)evaluateScript:(NSString *)script { return [self evaluateScript:script withSourceURL:nil]; }

- (JSValue *)evaluateScript:(NSString *)script withSourceURL:(NSURL *)sourceURL
{
    DrainPending();
    JSStringRef s = JSCString(script);
    JSStringRef url = sourceURL ? JSCString(sourceURL.absoluteString) : NULL;
    JSValueRef exception = NULL;
    JSValueRef v = JSEvaluateScript(_ctx, s, NULL, url, 1, &exception);
    JSStringRelease(s);
    if (url)
        JSStringRelease(url);
    if (exception) {
        [self _notifyException:exception];
        return [JSValue valueWithUndefinedInContext:self];
    }
    return [JSValue valueWithJSValueRef:v inContext:self];
}

- (void)_notifyException:(JSValueRef)exception
{
    JSValue *e = [JSValue valueWithJSValueRef:exception inContext:self];
    if (_handler)
        _handler(self, e);
    else
        self.exception = e;
}

- (JSValue *)exception { return [[_exception retain] autorelease]; }
- (void)setException:(JSValue *)exception
{
    [exception retain];
    [_exception release];
    _exception = exception;
}

- (void (^)(JSContext *, JSValue *))exceptionHandler { return [[_handler retain] autorelease]; }
- (void)setExceptionHandler:(void (^)(JSContext *, JSValue *))handler
{
    id copy = [handler copy];
    [_handler release];
    _handler = copy;
}

- (NSString *)name { return [[_name retain] autorelease]; }
- (void)setName:(NSString *)name
{
    NSString *copy = [name copy];
    [_name release];
    _name = copy;
    JSStringRef s = name ? JSCString(name) : NULL;
    JSGlobalContextSetName(_ctx, s);
    if (s)
        JSStringRelease(s);
}

- (BOOL)isInspectable { return JSGlobalContextIsInspectable(_ctx); }
- (void)setInspectable:(BOOL)inspectable { JSGlobalContextSetInspectable(_ctx, inspectable); }

- (JSValue *)globalObject
{
    return [JSValue valueWithJSValueRef:JSContextGetGlobalObject(_ctx) inContext:self];
}

+ (JSContext *)currentContext { return current ? current->context : nil; }

+ (JSValue *)currentCallee
{
    return current && current->callee ? [JSValue valueWithJSValueRef:current->callee inContext:current->context]
                                      : nil;
}

+ (JSValue *)currentThis
{
    return current && current->thisObject
               ? [JSValue valueWithJSValueRef:current->thisObject inContext:current->context]
               : nil;
}

+ (NSArray *)currentArguments
{
    if (!current)
        return nil;
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:current->argc];
    for (size_t i = 0; i < current->argc; i++)
        [a addObject:[JSValue valueWithJSValueRef:current->argv[i] inContext:current->context]];
    return a;
}

- (JSValue *)objectForKeyedSubscript:(id)key { return [self.globalObject objectForKeyedSubscript:key]; }

- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key
{
    [self.globalObject setObject:object forKeyedSubscript:key];
}

@end

/* ---- JSValue ---------------------------------------------------------------------------- */

@implementation JSValue

+ (JSValue *)valueWithJSValueRef:(JSValueRef)value inContext:(JSContext *)context
{
    if (!context)
        return nil;
    JSValue *v = [[self alloc] init];
    v->_context = [context retain];
    v->_ref = value ? value : JSValueMakeUndefined(context->_ctx);
    JSValueProtect(context->_ctx, v->_ref);
    return [v autorelease];
}

- (void)dealloc
{
    if (_context)
        JSValueUnprotect(_context->_ctx, _ref);
    [_context release];
    [super dealloc];
}

- (JSValueRef)JSValueRef { return _ref; }
- (JSContext *)context { return _context; }

+ (JSValue *)valueWithObject:(id)value inContext:(JSContext *)context
{
    return [self valueWithJSValueRef:ValueFromObject(context, value) inContext:context];
}
+ (JSValue *)valueWithBool:(BOOL)value inContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSValueMakeBoolean(context->_ctx, value) inContext:context];
}
+ (JSValue *)valueWithDouble:(double)value inContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSValueMakeNumber(context->_ctx, value) inContext:context];
}
+ (JSValue *)valueWithInt32:(int32_t)value inContext:(JSContext *)context
{
    return [self valueWithDouble:value inContext:context];
}
+ (JSValue *)valueWithUInt32:(uint32_t)value inContext:(JSContext *)context
{
    return [self valueWithDouble:value inContext:context];
}
+ (JSValue *)valueWithNewObjectInContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSObjectMake(context->_ctx, NULL, NULL) inContext:context];
}
+ (JSValue *)valueWithNewArrayInContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSObjectMakeArray(context->_ctx, 0, NULL, NULL) inContext:context];
}
+ (JSValue *)valueWithNewRegularExpressionFromPattern:(NSString *)pattern
                                                flags:(NSString *)flags
                                            inContext:(JSContext *)context
{
    JSStringRef p = JSCString(pattern), f = JSCString(flags);
    JSValueRef args[2] = {JSValueMakeString(context->_ctx, p), JSValueMakeString(context->_ctx, f)};
    JSStringRelease(p);
    JSStringRelease(f);
    return [self valueWithJSValueRef:JSObjectMakeRegExp(context->_ctx, 2, args, NULL) inContext:context];
}
+ (JSValue *)valueWithNewErrorFromMessage:(NSString *)message inContext:(JSContext *)context
{
    return [self valueWithJSValueRef:ErrorValue(context->_ctx, message) inContext:context];
}
+ (JSValue *)valueWithNewSymbolFromDescription:(NSString *)description inContext:(JSContext *)context
{
    JSStringRef s = JSCString(description);
    JSValueRef v = JSValueMakeSymbol(context->_ctx, s);
    JSStringRelease(s);
    return [self valueWithJSValueRef:v inContext:context];
}
+ (JSValue *)valueWithNullInContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSValueMakeNull(context->_ctx) inContext:context];
}
+ (JSValue *)valueWithUndefinedInContext:(JSContext *)context
{
    return [self valueWithJSValueRef:JSValueMakeUndefined(context->_ctx) inContext:context];
}

- (id)toObject { return ObjectFromJS(_context, _ref, 0); }

- (id)toObjectOfClass:(Class)expectedClass
{
    id o = [self toObject];
    return [o isKindOfClass:expectedClass] ? o : nil;
}

- (BOOL)toBool { return JSValueToBoolean(_context->_ctx, _ref); }

- (double)toDouble
{
    JSValueRef e = NULL;
    double d = JSValueToNumber(_context->_ctx, _ref, &e);
    if (e) {
        [_context _notifyException:e];
        return __builtin_nan("");
    }
    return d;
}

/* ToInt32 and ToUint32 as ECMAScript gives them: modulo 2^32. */
static uint32_t Modulo32(double d)
{
    if (d != d || d == __builtin_inf() || d == -__builtin_inf())
        return 0;
    d = d < 0 ? -__builtin_floor(-d) : __builtin_floor(d);
    d = __builtin_fmod(d, 4294967296.0);
    if (d < 0)
        d += 4294967296.0;
    return (uint32_t)d;
}
- (int32_t)toInt32 { return (int32_t)Modulo32([self toDouble]); }
- (uint32_t)toUInt32 { return Modulo32([self toDouble]); }

- (NSNumber *)toNumber
{
    if (JSValueIsBoolean(_context->_ctx, _ref))
        return [self toBool] ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    return [NSNumber numberWithDouble:[self toDouble]];
}

- (NSString *)toString
{
    JSValueRef e = NULL;
    JSStringRef s = JSValueToStringCopy(_context->_ctx, _ref, &e);
    if (e) {
        [_context _notifyException:e];
        return nil;
    }
    NSString *r = NSStringFromJS(s);
    JSStringRelease(s);
    return r;
}

- (NSDate *)toDate
{
    if (JSValueIsDate(_context->_ctx, _ref) || JSValueIsNumber(_context->_ctx, _ref))
        return [NSDate dateWithTimeIntervalSince1970:[self toDouble] / 1000.0];
    if (JSValueIsString(_context->_ctx, _ref)) {
        JSValue *dateClass = _context[@"Date"];
        JSValue *d = [dateClass constructWithArguments:@[ self ]];
        return [NSDate dateWithTimeIntervalSince1970:[d toDouble] / 1000.0];
    }
    return nil;
}

- (NSArray *)toArray
{
    if (!JSValueIsObject(_context->_ctx, _ref))
        return nil;
    return ArrayFromJS(_context, _ref, 0); /* an array, or any object with a length */
}

- (NSDictionary *)toDictionary
{
    if (!JSValueIsObject(_context->_ctx, _ref))
        return nil;
    return DictionaryFromJS(_context, _ref, 0);
}

- (BOOL)isUndefined { return JSValueIsUndefined(_context->_ctx, _ref); }
- (BOOL)isNull { return JSValueIsNull(_context->_ctx, _ref); }
- (BOOL)isBoolean { return JSValueIsBoolean(_context->_ctx, _ref); }
- (BOOL)isNumber { return JSValueIsNumber(_context->_ctx, _ref); }
- (BOOL)isString { return JSValueIsString(_context->_ctx, _ref); }
- (BOOL)isObject { return JSValueIsObject(_context->_ctx, _ref); }
- (BOOL)isArray { return JSValueIsArray(_context->_ctx, _ref); }
- (BOOL)isDate { return JSValueIsDate(_context->_ctx, _ref); }
- (BOOL)isSymbol { return JSValueIsSymbol(_context->_ctx, _ref); }

- (BOOL)isEqualToObject:(id)value
{
    return JSValueIsStrictEqual(_context->_ctx, _ref, ValueFromObject(_context, value));
}

- (BOOL)isEqualWithTypeCoercionToObject:(id)value
{
    JSValueRef e = NULL;
    BOOL r = JSValueIsEqual(_context->_ctx, _ref, ValueFromObject(_context, value), &e);
    if (e)
        [_context _notifyException:e];
    return r;
}

- (BOOL)isInstanceOf:(id)value
{
    JSValueRef c = ValueFromObject(_context, value);
    if (!JSValueIsObject(_context->_ctx, c))
        return NO;
    JSValueRef e = NULL;
    BOOL r = JSValueIsInstanceOfConstructor(_context->_ctx, _ref, (JSObjectRef)c, &e);
    if (e)
        [_context _notifyException:e];
    return r;
}

/* The arguments as protected values, released by Unprotect. */
static JSValueRef *Arguments(JSContext *c, NSArray *arguments, size_t *count)
{
    size_t n = arguments.count;
    *count = n;
    JSValueRef *argv = calloc(n ? n : 1, sizeof *argv);
    for (size_t i = 0; i < n; i++) {
        argv[i] = ValueFromObject(c, arguments[i]);
        JSValueProtect(c->_ctx, argv[i]);
    }
    return argv;
}

static void Unprotect(JSContext *c, JSValueRef *argv, size_t n)
{
    for (size_t i = 0; i < n; i++)
        JSValueUnprotect(c->_ctx, argv[i]);
    free(argv);
}

- (JSValue *)_finish:(JSValueRef)result exception:(JSValueRef)exception
{
    if (exception) {
        [_context _notifyException:exception];
        return [JSValue valueWithUndefinedInContext:_context];
    }
    return [JSValue valueWithJSValueRef:result inContext:_context];
}

- (JSValue *)callWithArguments:(NSArray *)arguments
{
    DrainPending();
    JSContextRef ctx = _context->_ctx;
    if (!JSValueIsObject(ctx, _ref) || !JSObjectIsFunction(ctx, (JSObjectRef)_ref))
        return [self _finish:NULL exception:ErrorValue(ctx, @"TypeError: the value is not a function")];
    size_t n;
    JSValueRef *argv = Arguments(_context, arguments, &n);
    JSValueRef e = NULL;
    JSValueRef r = JSObjectCallAsFunction(ctx, (JSObjectRef)_ref, NULL, n, argv, &e);
    Unprotect(_context, argv, n);
    return [self _finish:r exception:e];
}

- (JSValue *)constructWithArguments:(NSArray *)arguments
{
    DrainPending();
    JSContextRef ctx = _context->_ctx;
    if (!JSValueIsObject(ctx, _ref) || !JSObjectIsConstructor(ctx, (JSObjectRef)_ref))
        return [self _finish:NULL exception:ErrorValue(ctx, @"TypeError: the value is not a constructor")];
    size_t n;
    JSValueRef *argv = Arguments(_context, arguments, &n);
    JSValueRef e = NULL;
    JSValueRef r = JSObjectCallAsConstructor(ctx, (JSObjectRef)_ref, n, argv, &e);
    Unprotect(_context, argv, n);
    return [self _finish:r exception:e];
}

- (JSValue *)invokeMethod:(NSString *)method withArguments:(NSArray *)arguments
{
    DrainPending();
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    if (e)
        return [self _finish:NULL exception:e];
    JSStringRef s = JSCString(method);
    JSValueRef f = JSObjectGetProperty(ctx, o, s, &e);
    JSStringRelease(s);
    if (e)
        return [self _finish:NULL exception:e];
    if (!JSValueIsObject(ctx, f) || !JSObjectIsFunction(ctx, (JSObjectRef)f))
        return [self _finish:NULL
                   exception:ErrorValue(ctx, [NSString stringWithFormat:@"TypeError: %@ is not a function", method])];
    size_t n;
    JSValueRef *argv = Arguments(_context, arguments, &n);
    JSValueRef r = JSObjectCallAsFunction(ctx, (JSObjectRef)f, o, n, argv, &e);
    Unprotect(_context, argv, n);
    return [self _finish:r exception:e];
}

- (NSString *)description
{
    NSString *s = [self toString];
    return s ? s : @"undefined";
}

@end

@implementation JSValue (StructSupport)

+ (JSValue *)valueWithPoint:(CGPoint)point inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"x" : @(point.x), @"y" : @(point.y)} inContext:context];
}
+ (JSValue *)valueWithRange:(NSRange)range inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"location" : @(range.location), @"length" : @(range.length)}
                       inContext:context];
}
+ (JSValue *)valueWithRect:(CGRect)rect inContext:(JSContext *)context
{
    return [self valueWithObject:@{
        @"x" : @(rect.origin.x),
        @"y" : @(rect.origin.y),
        @"width" : @(rect.size.width),
        @"height" : @(rect.size.height)
    }
                       inContext:context];
}
+ (JSValue *)valueWithSize:(CGSize)size inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"width" : @(size.width), @"height" : @(size.height)} inContext:context];
}
- (CGPoint)toPoint
{
    JSContextRef ctx = _context->_ctx;
    return CGPointMake(NumberProperty(ctx, _ref, "x"), NumberProperty(ctx, _ref, "y"));
}
- (NSRange)toRange
{
    JSContextRef ctx = _context->_ctx;
    return NSMakeRange((NSUInteger)NumberProperty(ctx, _ref, "location"),
                       (NSUInteger)NumberProperty(ctx, _ref, "length"));
}
- (CGRect)toRect
{
    JSContextRef ctx = _context->_ctx;
    return CGRectMake(NumberProperty(ctx, _ref, "x"), NumberProperty(ctx, _ref, "y"),
                      NumberProperty(ctx, _ref, "width"), NumberProperty(ctx, _ref, "height"));
}
- (CGSize)toSize
{
    JSContextRef ctx = _context->_ctx;
    return CGSizeMake(NumberProperty(ctx, _ref, "width"), NumberProperty(ctx, _ref, "height"));
}

@end

@implementation JSValue (PropertyAccess)

- (JSValue *)valueForProperty:(id)property
{
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    if (e)
        return [self _finish:NULL exception:e];
    JSValueRef key = ValueFromObject(_context, [property isKindOfClass:[NSNumber class]] ? property : KeyString(property));
    JSValueRef r = JSObjectGetPropertyForKey(ctx, o, key, &e);
    return [self _finish:r exception:e];
}

- (void)setValue:(id)value forProperty:(id)property
{
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    if (!e) {
        JSValueRef key =
            ValueFromObject(_context, [property isKindOfClass:[NSNumber class]] ? property : KeyString(property));
        JSValueProtect(ctx, key);
        JSValueRef v = ValueFromObject(_context, value);
        JSObjectSetPropertyForKey(ctx, o, key, v, kJSPropertyAttributeNone, &e);
        JSValueUnprotect(ctx, key);
    }
    if (e)
        [_context _notifyException:e];
}

- (BOOL)deleteProperty:(id)property
{
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    BOOL r = NO;
    if (!e)
        r = JSObjectDeletePropertyForKey(ctx, o, ValueFromObject(_context, KeyString(property)), &e);
    if (e)
        [_context _notifyException:e];
    return r;
}

- (BOOL)hasProperty:(id)property
{
    JSContextRef ctx = _context->_ctx;
    if (!JSValueIsObject(ctx, _ref))
        return NO;
    JSValueRef e = NULL;
    BOOL r = JSObjectHasPropertyForKey(ctx, (JSObjectRef)_ref, ValueFromObject(_context, KeyString(property)), &e);
    if (e)
        [_context _notifyException:e];
    return r;
}

- (void)defineProperty:(id)property descriptor:(id)descriptor
{
    JSValue *object = _context[@"Object"];
    [object invokeMethod:@"defineProperty" withArguments:@[ self, KeyString(property), descriptor ? descriptor : @{} ]];
}

- (JSValue *)valueAtIndex:(NSUInteger)index
{
    if (index > 0xfffffffeu)
        return [self valueForProperty:[@(index) description]];
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    if (e)
        return [self _finish:NULL exception:e];
    JSValueRef r = JSObjectGetPropertyAtIndex(ctx, o, (unsigned)index, &e);
    return [self _finish:r exception:e];
}

- (void)setValue:(id)value atIndex:(NSUInteger)index
{
    if (index > 0xfffffffeu) {
        [self setValue:value forProperty:[@(index) description]];
        return;
    }
    JSContextRef ctx = _context->_ctx;
    JSValueRef e = NULL;
    JSObjectRef o = JSValueToObject(ctx, _ref, &e);
    if (!e)
        JSObjectSetPropertyAtIndex(ctx, o, (unsigned)index, ValueFromObject(_context, value), &e);
    if (e)
        [_context _notifyException:e];
}

@end

@implementation JSValue (SubscriptSupport)
- (JSValue *)objectForKeyedSubscript:(id)key { return [self valueForProperty:key]; }
- (JSValue *)objectAtIndexedSubscript:(NSUInteger)index { return [self valueAtIndex:index]; }
- (void)setObject:(id)object forKeyedSubscript:(id)key { [self setValue:object forProperty:key]; }
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index { [self setValue:object atIndex:index]; }
@end

/* ---- JSManagedValue --------------------------------------------------------------------- */

@implementation JSManagedValue {
    JSValue *_value;
}
+ (JSManagedValue *)managedValueWithValue:(JSValue *)value
{
    return [[[self alloc] initWithValue:value] autorelease];
}
+ (JSManagedValue *)managedValueWithValue:(JSValue *)value andOwner:(id)owner
{
    return [self managedValueWithValue:value];
}
- (instancetype)initWithValue:(JSValue *)value
{
    if ((self = [super init]))
        _value = [value retain];
    return self;
}
- (void)dealloc
{
    [_value release];
    [super dealloc];
}
- (JSValue *)value { return [[_value retain] autorelease]; }
@end
