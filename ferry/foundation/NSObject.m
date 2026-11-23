/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: what NSObject gains from Foundation (descriptions and
 * simple key-value coding), NSError, NSException, NSAutoreleasePool, NSLog,
 * the NSStringFrom... functions, home and search paths, and the
 * old-style property list text that collections print as their description. */
#import "FInternal.h"
#include <pwd.h>
#include <unistd.h>
#include <time.h>
#include <sys/time.h>

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *token);

NSString *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
NSString *const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSString *const NSFilePathErrorKey = @"NSFilePath";
NSString *const NSUnderlyingErrorKey = @"NSUnderlyingError";
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

@implementation NSObject (NSObjectFoundation)
- (NSString *)description { return [NSString stringWithFormat:@"<%s: %p>", object_getClassName(self), self]; }
- (NSString *)debugDescription { return [self description]; }
+ (NSString *)description { return [NSString stringWithUTF8String:class_getName(self)]; }
+ (NSString *)debugDescription { return [self description]; }
- (NSString *)className { return [NSString stringWithUTF8String:object_getClassName(self)]; }

static id box(id self, SEL sel, char type)
{
    switch (type) {
    case '@':
    case '#': return ((id (*)(id, SEL))objc_msgSend)(self, sel);
    case 'c':
    case 'B': return [NSNumber numberWithBool:((BOOL (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'i': return [NSNumber numberWithInt:((int (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'I': return [NSNumber numberWithUnsignedInt:((unsigned (*)(id, SEL))objc_msgSend)(self, sel)];
    case 's': return [NSNumber numberWithShort:((short (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'q':
    case 'l': return [NSNumber numberWithLongLong:((long long (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'Q':
    case 'L': return [NSNumber numberWithUnsignedLongLong:((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'f': return [NSNumber numberWithFloat:((float (*)(id, SEL))objc_msgSend)(self, sel)];
    case 'd': return [NSNumber numberWithDouble:((double (*)(id, SEL))objc_msgSend)(self, sel)];
    }
    return nil;
}

- (id)valueForKey:(NSString *)key
{
    const char *k = [key UTF8String];
    Class cls = object_getClass(self);
    char name[256];
    SEL sel = sel_registerName(k);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m && k[0]) {
        snprintf(name, sizeof name, "is%c%s", toupper((unsigned char)k[0]), k + 1);
        sel = sel_registerName(name);
        m = class_getInstanceMethod(cls, sel);
    }
    if (m)
        return box(self, sel, method_getTypeEncoding(m)[0]);
    snprintf(name, sizeof name, "_%s", k);
    Ivar v = class_getInstanceVariable(cls, name);
    if (!v)
        v = class_getInstanceVariable(cls, k);
    if (v && ivar_getTypeEncoding(v)[0] == '@')
        return object_getIvar(self, v);
    FRaise(@"NSUnknownKeyException", @"[<%s %p> valueForUndefinedKey:]: this class is not key value coding-compliant "
                                     @"for the key %@.",
           object_getClassName(self), self, key);
}

/* Observers of the key hear of the change (NSKeyValueObserving.m). */
- (void)setValue:(id)value forKey:(NSString *)key
{
    BOOL observed = FKVOIsObserved(self);
    if (observed)
        [self willChangeValueForKey:key];
    [self _ferrySetValue:value forKey:key];
    if (observed)
        [self didChangeValueForKey:key];
}
- (void)_ferrySetValue:(id)value forKey:(NSString *)key
{
    const char *k = [key UTF8String];
    char name[256];
    snprintf(name, sizeof name, "set%c%s:", toupper((unsigned char)k[0]), k + 1);
    SEL sel = sel_registerName(name);
    Method m = class_getInstanceMethod(object_getClass(self), sel);
    if (m) {
        char t[16];
        method_getArgumentType(m, 2, t, sizeof t);
        switch (t[0]) {
        case '@': ((void (*)(id, SEL, id))objc_msgSend)(self, sel, value); return;
        case 'c':
        case 'B': ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel, [value boolValue]); return;
        case 'i': ((void (*)(id, SEL, int))objc_msgSend)(self, sel, [value intValue]); return;
        case 'q':
        case 'Q':
        case 'l':
        case 'L': ((void (*)(id, SEL, long long))objc_msgSend)(self, sel, [value longLongValue]); return;
        case 'f': ((void (*)(id, SEL, float))objc_msgSend)(self, sel, [value floatValue]); return;
        case 'd': ((void (*)(id, SEL, double))objc_msgSend)(self, sel, [value doubleValue]); return;
        }
    }
    snprintf(name, sizeof name, "_%s", k);
    Ivar v = class_getInstanceVariable(object_getClass(self), name);
    if (!v)
        v = class_getInstanceVariable(object_getClass(self), k);
    if (v && ivar_getTypeEncoding(v)[0] == '@') {
        id old = object_getIvar(self, v);
        object_setIvar(self, v, [value retain]);
        [old release];
        return;
    }
    FRaise(@"NSUnknownKeyException", @"[<%s %p> setValue:forUndefinedKey:]: this class is not key value "
                                     @"coding-compliant for the key %@.",
           object_getClassName(self), self, key);
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

static NSString *xdg_dir(const char *var, NSString *fallback)
{
    const char *x = getenv(var);
    if (x && x[0] == '/')
        return [NSString stringWithUTF8String:x];
    return [FHome() stringByAppendingPathComponent:fallback];
}

NSString *NSHomeDirectory(void) { return FHome(); }
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

/* Where a Mac app's folders are on freemac. Only the user domain has folders;
 * the Mac's /Library and /System/Library have no counterpart here. */
NSString *FUserFolder(NSSearchPathDirectory dir)
{
    switch (dir) {
    case NSApplicationDirectory: return [FHome() stringByAppendingPathComponent:@"Applications"];
    case NSLibraryDirectory:
    case NSApplicationSupportDirectory: return xdg_dir("XDG_DATA_HOME", @".local/share");
    case NSCachesDirectory: return xdg_dir("XDG_CACHE_HOME", @".cache");
    case NSDocumentDirectory: return [FHome() stringByAppendingPathComponent:@"Documents"];
    case NSDesktopDirectory: return [FHome() stringByAppendingPathComponent:@"Desktop"];
    case NSDownloadsDirectory: return [FHome() stringByAppendingPathComponent:@"Downloads"];
    case NSMoviesDirectory: return [FHome() stringByAppendingPathComponent:@"Videos"];
    case NSMusicDirectory: return [FHome() stringByAppendingPathComponent:@"Music"];
    case NSPicturesDirectory: return [FHome() stringByAppendingPathComponent:@"Pictures"];
    case NSUserDirectory: return [FHome() stringByDeletingLastPathComponent];
    }
    return nil;
}

NSArray *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory dir, NSSearchPathDomainMask mask, BOOL expandTilde)
{
    NSString *p = (mask & NSUserDomainMask) ? FUserFolder(dir) : nil;
    if (!p)
        return [NSArray array];
    if (!expandTilde)
        p = [p stringByAbbreviatingWithTildeInPath];
    return [NSArray arrayWithObject:p];
}
