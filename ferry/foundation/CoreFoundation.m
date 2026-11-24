/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's CoreFoundation basics. In Ferry every CF object is the matching
 * Foundation object (a CFStringRef is an NSString, a CFRunLoopRef the
 * NSRunLoop, and so on), so these C functions are thin wrappers and
 * "toll-free bridging" holds by construction. The loader serves
 * CoreFoundation.framework from Foundation's file. */
#import "FInternal.h"
#include <sys/time.h>
#include <dlfcn.h>

const CFAllocatorRef kCFAllocatorDefault = NULL;
const CFAllocatorRef kCFAllocatorSystemDefault = NULL;
const CFAllocatorRef kCFAllocatorNull = NULL;
const CFRunLoopMode kCFRunLoopDefaultMode = (CFStringRef)@"kCFRunLoopDefaultMode";
const CFRunLoopMode kCFRunLoopCommonModes = (CFStringRef)@"kCFRunLoopCommonModes";
const CFTimeInterval kCFAbsoluteTimeIntervalSince1970 = 978307200.0;
const char kCFTypeArrayCallBacks[1];
const char kCFTypeDictionaryKeyCallBacks[1];
const char kCFTypeDictionaryValueCallBacks[1];

#define OBJ(x) ((id)(x))

CFTypeRef CFRetain(CFTypeRef cf) { return [OBJ(cf) retain]; }
void CFRelease(CFTypeRef cf) { [OBJ(cf) release]; }
CFTypeRef CFAutorelease(CFTypeRef cf) { return [OBJ(cf) autorelease]; }
CFIndex CFGetRetainCount(CFTypeRef cf) { return (CFIndex)[OBJ(cf) retainCount]; }
Boolean CFEqual(CFTypeRef a, CFTypeRef b) { return a == b || [OBJ(a) isEqual:OBJ(b)]; }
CFHashCode CFHash(CFTypeRef cf) { return [OBJ(cf) hash]; }
CFStringRef CFCopyDescription(CFTypeRef cf) { return (CFStringRef)[[OBJ(cf) description] copy]; }
void CFShow(CFTypeRef obj)
{
    fflush(stdout);
    fprintf(stderr, "%s\n", obj ? [[OBJ(obj) description] UTF8String] : "(null)");
}

/* ---- strings ------------------------------------------------------------------------- */

static NSStringEncoding ns_encoding(CFStringEncoding enc)
{
    switch (enc) {
    case kCFStringEncodingASCII: return NSASCIIStringEncoding;
    case kCFStringEncodingISOLatin1: return NSISOLatin1StringEncoding;
    case kCFStringEncodingUnicode: return NSUnicodeStringEncoding;
    default: return NSUTF8StringEncoding;
    }
}

CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char *s, CFStringEncoding enc)
{
    return (CFStringRef)[[NSString alloc] initWithCString:s encoding:ns_encoding(enc)];
}
CFStringRef CFStringCreateWithCharacters(CFAllocatorRef alloc, const UniChar *chars, CFIndex len)
{
    return (CFStringRef)[[NSString alloc] initWithCharacters:chars length:len];
}
CFStringRef CFStringCreateWithFormat(CFAllocatorRef alloc, CFDictionaryRef options, CFStringRef format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *s = FFormat((NSString *)format, ap);
    va_end(ap);
    return (CFStringRef)[s copy];
}
CFStringRef CFStringCreateCopy(CFAllocatorRef alloc, CFStringRef s) { return (CFStringRef)[OBJ(s) copy]; }
CFMutableStringRef CFStringCreateMutable(CFAllocatorRef alloc, CFIndex max)
{
    return (CFMutableStringRef)[[NSMutableString alloc] init];
}
void CFStringAppend(CFMutableStringRef s, CFStringRef appended) { [OBJ(s) appendString:OBJ(appended)]; }
void CFStringAppendCString(CFMutableStringRef s, const char *cstr, CFStringEncoding enc)
{
    [OBJ(s) appendString:[NSString stringWithCString:cstr encoding:ns_encoding(enc)]];
}
CFIndex CFStringGetLength(CFStringRef s) { return (CFIndex)[OBJ(s) length]; }
UniChar CFStringGetCharacterAtIndex(CFStringRef s, CFIndex i) { return [OBJ(s) characterAtIndex:i]; }
Boolean CFStringGetCString(CFStringRef s, char *buffer, CFIndex size, CFStringEncoding enc)
{
    return [OBJ(s) getCString:buffer maxLength:size encoding:ns_encoding(enc)];
}
const char *CFStringGetCStringPtr(CFStringRef s, CFStringEncoding enc)
{
    if (enc != kCFStringEncodingUTF8 && enc != kCFStringEncodingASCII)
        return NULL;
    const char *p = [OBJ(s) UTF8String];
    if (enc == kCFStringEncodingASCII)
        for (const char *q = p; *q; q++)
            if (*q & 0x80)
                return NULL;
    return p;
}
/* "May return NULL at any time", as the documentation says: callers then
 * copy the characters with CFStringGetCharacters. */
const UniChar *CFStringGetCharactersPtr(CFStringRef s) { return NULL; }
void CFStringGetCharacters(CFStringRef s, CFRange range, UniChar *buffer)
{
    [OBJ(s) getCharacters:buffer range:NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length)];
}
CFComparisonResult CFStringCompare(CFStringRef a, CFStringRef b, CFOptionFlags options)
{
    return (CFComparisonResult)[OBJ(a) compare:OBJ(b) options:options];
}
Boolean CFStringHasPrefix(CFStringRef s, CFStringRef prefix) { return [OBJ(s) hasPrefix:OBJ(prefix)]; }
Boolean CFStringHasSuffix(CFStringRef s, CFStringRef suffix) { return [OBJ(s) hasSuffix:OBJ(suffix)]; }
SInt32 CFStringGetIntValue(CFStringRef s) { return [OBJ(s) intValue]; }
double CFStringGetDoubleValue(CFStringRef s) { return [OBJ(s) doubleValue]; }

/* ---- arrays and dictionaries (with the CFType callbacks only) ----------------------------- */

CFIndex CFArrayGetCount(CFArrayRef a) { return (CFIndex)[OBJ(a) count]; }
const void *CFArrayGetValueAtIndex(CFArrayRef a, CFIndex i) { return [OBJ(a) objectAtIndex:i]; }
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const void *callbacks)
{
    return (CFMutableArrayRef)[[NSMutableArray alloc] init];
}
void CFArrayAppendValue(CFMutableArrayRef a, const void *value) { [OBJ(a) addObject:OBJ(value)]; }

CFIndex CFDictionaryGetCount(CFDictionaryRef d) { return (CFIndex)[OBJ(d) count]; }
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *key) { return [OBJ(d) objectForKey:OBJ(key)]; }
Boolean CFDictionaryContainsKey(CFDictionaryRef d, const void *key) { return [OBJ(d) objectForKey:OBJ(key)] != nil; }
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const void *keyCallBacks,
                                                 const void *valueCallBacks)
{
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] init];
}
void CFDictionarySetValue(CFMutableDictionaryRef d, const void *key, const void *value)
{
    [OBJ(d) setObject:OBJ(value) forKey:OBJ(key)];
}
void CFDictionaryRemoveValue(CFMutableDictionaryRef d, const void *key) { [OBJ(d) removeObjectForKey:OBJ(key)]; }

/* ---- numbers, booleans, data, time ----------------------------------------------------------- */

CFNumberRef CFNumberCreate(CFAllocatorRef alloc, CFNumberType type, const void *value)
{
    NSNumber *n;
    switch (type) {
    case kCFNumberSInt8Type:
    case kCFNumberCharType: n = [NSNumber numberWithChar:*(const char *)value]; break;
    case kCFNumberSInt16Type:
    case kCFNumberShortType: n = [NSNumber numberWithShort:*(const short *)value]; break;
    case kCFNumberSInt32Type:
    case kCFNumberIntType: n = [NSNumber numberWithInt:*(const int *)value]; break;
    case kCFNumberFloat32Type:
    case kCFNumberFloatType: n = [NSNumber numberWithFloat:*(const float *)value]; break;
    case kCFNumberFloat64Type:
    case kCFNumberDoubleType:
    case kCFNumberCGFloatType: n = [NSNumber numberWithDouble:*(const double *)value]; break;
    default: n = [NSNumber numberWithLongLong:*(const long long *)value]; break;
    }
    return (CFNumberRef)[n retain];
}

Boolean CFNumberGetValue(CFNumberRef number, CFNumberType type, void *value)
{
    NSNumber *n = OBJ(number);
    switch (type) {
    case kCFNumberSInt8Type:
    case kCFNumberCharType: *(char *)value = [n charValue]; break;
    case kCFNumberSInt16Type:
    case kCFNumberShortType: *(short *)value = [n shortValue]; break;
    case kCFNumberSInt32Type:
    case kCFNumberIntType: *(int *)value = [n intValue]; break;
    case kCFNumberFloat32Type:
    case kCFNumberFloatType: *(float *)value = [n floatValue]; break;
    case kCFNumberFloat64Type:
    case kCFNumberDoubleType:
    case kCFNumberCGFloatType: *(double *)value = [n doubleValue]; break;
    default: *(long long *)value = [n longLongValue]; break;
    }
    return YES;
}

Boolean CFBooleanGetValue(CFBooleanRef b) { return [OBJ(b) boolValue]; }

CFDataRef CFDataCreate(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length)
{
    return (CFDataRef)[[NSData alloc] initWithBytes:bytes length:length];
}
CFIndex CFDataGetLength(CFDataRef d) { return (CFIndex)[OBJ(d) length]; }
const UInt8 *CFDataGetBytePtr(CFDataRef d) { return [OBJ(d) bytes]; }

CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) { return [NSDate timeIntervalSinceReferenceDate]; }

/* ---- run loops and bundles ------------------------------------------------------------------- */

@interface NSRunLoop (Ferry)
- (void)stop;
- (SInt32)runFor:(CFTimeInterval)seconds returnAfterSource:(BOOL)once;
@end

CFRunLoopRef CFRunLoopGetCurrent(void) { return (CFRunLoopRef)[NSRunLoop currentRunLoop]; }
CFRunLoopRef CFRunLoopGetMain(void) { return (CFRunLoopRef)[NSRunLoop mainRunLoop]; }
void CFRunLoopRun(void)
{
    SInt32 r;
    do
        r = [[NSRunLoop currentRunLoop] runFor:1e10 returnAfterSource:NO];
    while (r == kCFRunLoopRunTimedOut);
}
SInt32 CFRunLoopRunInMode(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled)
{
    return [[NSRunLoop currentRunLoop] runFor:seconds returnAfterSource:returnAfterSourceHandled];
}
void CFRunLoopStop(CFRunLoopRef rl) { [OBJ(rl) stop]; }
void CFRunLoopWakeUp(CFRunLoopRef rl) {}
void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void)) { [OBJ(rl) performBlock:block]; }

CFBundleRef CFBundleGetMainBundle(void) { return (CFBundleRef)[NSBundle mainBundle]; }
CFTypeRef CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key)
{
    return [OBJ(bundle) objectForInfoDictionaryKey:OBJ(key)];
}
CFStringRef CFBundleGetIdentifier(CFBundleRef bundle) { return (CFStringRef)[OBJ(bundle) bundleIdentifier]; }

/* A CFBundle is the NSBundle for the same folder; its program is loaded
 * with dlopen and its functions found with dlsym (src/dyld.c). */
@interface NSBundle (FerryHandle)
- (void *)_ferryHandle;
@end
CFBundleRef CFBundleCreate(CFAllocatorRef alloc, CFURLRef url)
{
    return (CFBundleRef)[[NSBundle alloc] initWithURL:OBJ(url)];
}
CFBundleRef CFBundleGetBundleWithIdentifier(CFStringRef identifier)
{
    return (CFBundleRef)[NSBundle bundleWithIdentifier:OBJ(identifier)];
}
CFURLRef CFBundleCopyBundleURL(CFBundleRef bundle) { return (CFURLRef)[[OBJ(bundle) bundleURL] retain]; }
CFURLRef CFBundleCopyExecutableURL(CFBundleRef bundle) { return (CFURLRef)[[OBJ(bundle) executableURL] retain]; }
CFURLRef CFBundleCopyResourcesDirectoryURL(CFBundleRef bundle) { return (CFURLRef)[[OBJ(bundle) resourceURL] retain]; }
CFURLRef CFBundleCopyBuiltInPlugInsURL(CFBundleRef bundle)
{
    return (CFURLRef)[[OBJ(bundle) builtInPlugInsURL] retain];
}
CFDictionaryRef CFBundleGetInfoDictionary(CFBundleRef bundle) { return (CFDictionaryRef)[OBJ(bundle) infoDictionary]; }
Boolean CFBundleLoadExecutable(CFBundleRef bundle) { return [OBJ(bundle) load]; }
Boolean CFBundleLoadExecutableAndReturnError(CFBundleRef bundle, CFErrorRef *error)
{
    NSError *e = nil;
    BOOL ok = [OBJ(bundle) loadAndReturnError:error ? &e : NULL];
    if (error)
        *error = ok ? NULL : (CFErrorRef)[e retain];
    return ok;
}
Boolean CFBundleIsExecutableLoaded(CFBundleRef bundle) { return [OBJ(bundle) isLoaded]; }
void CFBundleUnloadExecutable(CFBundleRef bundle) {}
void *CFBundleGetFunctionPointerForName(CFBundleRef bundle, CFStringRef name)
{
    void *handle = [OBJ(bundle) _ferryHandle];
    return handle && name ? dlsym(handle, [OBJ(name) UTF8String]) : NULL;
}
void *CFBundleGetDataPointerForName(CFBundleRef bundle, CFStringRef name)
{
    return CFBundleGetFunctionPointerForName(bundle, name);
}
void CFBundleGetFunctionPointersForNames(CFBundleRef bundle, CFArrayRef names, void *pointers[])
{
    CFIndex n = [OBJ(names) count];
    for (CFIndex i = 0; i < n; i++)
        pointers[i] = CFBundleGetFunctionPointerForName(bundle, (CFStringRef)[OBJ(names) objectAtIndex:i]);
}

/* ---- preferences: the NSUserDefaults store, by application id -------------------------- */

const CFStringRef kCFPreferencesAnyApplication = (CFStringRef)@"kCFPreferencesAnyApplication";
const CFStringRef kCFPreferencesCurrentApplication = (CFStringRef)@"kCFPreferencesCurrentApplication";
const CFStringRef kCFPreferencesAnyHost = (CFStringRef)@"kCFPreferencesAnyHost";
const CFStringRef kCFPreferencesCurrentHost = (CFStringRef)@"kCFPreferencesCurrentHost";
const CFStringRef kCFPreferencesAnyUser = (CFStringRef)@"kCFPreferencesAnyUser";
const CFStringRef kCFPreferencesCurrentUser = (CFStringRef)@"kCFPreferencesCurrentUser";

static NSUserDefaults *prefs_for(CFStringRef app)
{
    static NSMutableDictionary *others;
    NSString *name = OBJ(app);
    if (!name || [name isEqual:OBJ(kCFPreferencesCurrentApplication)] ||
        [name isEqual:[[NSBundle mainBundle] bundleIdentifier]])
        return [NSUserDefaults standardUserDefaults];
    if (!others)
        others = [[NSMutableDictionary alloc] init];
    NSUserDefaults *d = [others objectForKey:name];
    if (!d) {
        d = [[NSUserDefaults alloc] initWithSuiteName:name];
        [others setObject:d forKey:name];
        [d release];
    }
    return d;
}

CFPropertyListRef CFPreferencesCopyAppValue(CFStringRef key, CFStringRef app)
{
    return [[prefs_for(app) objectForKey:OBJ(key)] copy];
}
Boolean CFPreferencesGetAppBooleanValue(CFStringRef key, CFStringRef app, Boolean *valid)
{
    id v = [prefs_for(app) objectForKey:OBJ(key)];
    BOOL ok = [v respondsToSelector:@selector(boolValue)];
    if (valid)
        *valid = ok;
    return ok ? [prefs_for(app) boolForKey:OBJ(key)] : false;
}
CFIndex CFPreferencesGetAppIntegerValue(CFStringRef key, CFStringRef app, Boolean *valid)
{
    id v = [prefs_for(app) objectForKey:OBJ(key)];
    BOOL ok = [v respondsToSelector:@selector(integerValue)];
    if (valid)
        *valid = ok;
    return ok ? [v integerValue] : 0;
}
void CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef app)
{
    [prefs_for(app) setObject:OBJ(value) forKey:OBJ(key)];
}
Boolean CFPreferencesAppSynchronize(CFStringRef app) { return [prefs_for(app) synchronize]; }
Boolean CFPreferencesAppValueIsForced(CFStringRef key, CFStringRef app) { return false; }
CFPropertyListRef CFPreferencesCopyValue(CFStringRef key, CFStringRef app, CFStringRef user, CFStringRef host)
{
    return CFPreferencesCopyAppValue(key, app);
}
void CFPreferencesSetValue(CFStringRef key, CFPropertyListRef value, CFStringRef app, CFStringRef user, CFStringRef host)
{
    CFPreferencesSetAppValue(key, value, app);
}
CFDictionaryRef CFPreferencesCopyMultiple(CFArrayRef keys, CFStringRef app, CFStringRef user, CFStringRef host)
{
    NSUserDefaults *d = prefs_for(app);
    NSMutableDictionary *out = [[NSMutableDictionary alloc] init];
    NSArray *want = keys ? OBJ(keys) : [[d dictionaryRepresentation] allKeys];
    for (NSString *k in want) {
        id v = [d objectForKey:k];
        if (v)
            [out setObject:v forKey:k];
    }
    return (CFDictionaryRef)out;
}
Boolean CFPreferencesSynchronize(CFStringRef app, CFStringRef user, CFStringRef host) { return true; }
CFArrayRef CFPreferencesCopyKeyList(CFStringRef app, CFStringRef user, CFStringRef host)
{
    NSUserDefaults *d = prefs_for(app);
    NSDictionary *saved = [d persistentDomainForName:[d _ferryDomain]];
    return [saved count] ? (CFArrayRef)[[saved allKeys] copy] : NULL;
}
