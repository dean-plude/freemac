/* SPDX-License-Identifier: GPL-3.0-or-later
 * Scripting Bridge (freemac 1.223, Ferry 0.47.0), written from Apple's
 * public documentation. A Mac's sends Apple events to another app; this
 * system has neither Apple events nor the Mac's scriptable apps, so:
 * - an app looked up by bundle identifier or URL is found only if Launch
 *   Services knows it (NSWorkspace), and otherwise the lookup answers nil,
 *   as a Mac's does for an app that isn't installed;
 * - an app object, and every object reached from it, answers nil (or 0, or
 *   NO) to the properties and commands that the app's generated header
 *   declares, does nothing, and tells its delegate (eventDidFail:withError:)
 *   that the event failed, with errAEEventNotHandled; and its element
 *   arrays are empty. */
#import "AInternal.h"
#import <ScriptingBridge/ScriptingBridge.h>

static NSError *not_handled(void)
{
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:errAEEventNotHandled
                           userInfo:@{NSLocalizedDescriptionKey : @"This system has no Apple events, so the app can't "
                                                                  @"be scripted."}];
}

@interface SBObject ()
- (SBApplication *)_application;
- (void)_setApplication:(SBApplication *)app;
- (void)_failed;
@end

@implementation SBObject {
    SBApplication *_app; /* not retained: the app outlives what it hands out */
    NSError *_error;
    NSDictionary *_properties;
}
- (instancetype)init { return [super init]; }
- (instancetype)initWithProperties:(NSDictionary *)properties
{
    if ((self = [super init]))
        _properties = [properties copy];
    return self;
}
- (instancetype)initWithData:(id)data { return [self init]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    [_error release];
    [_properties release];
    [super dealloc];
}
- (SBApplication *)_application { return _app; }
- (void)_setApplication:(SBApplication *)app { _app = app; }
- (void)_failed
{
    [_error release];
    _error = [not_handled() retain];
    id<SBApplicationDelegate> d = [_app delegate];
    if ([d respondsToSelector:@selector(eventDidFail:withError:)])
        [d eventDidFail:NULL withError:_error];
}
- (id)get
{
    [self _failed];
    return nil;
}
- (NSError *)lastError { return _error; }
- (SBObject *)propertyWithCode:(AEKeyword)code { return [self propertyWithClass:[SBObject class] code:code]; }
- (SBObject *)propertyWithClass:(Class)cls code:(AEKeyword)code
{
    SBObject *o = [[[(cls ?: [SBObject class]) alloc] init] autorelease];
    [o _setApplication:_app];
    return o;
}
- (SBElementArray *)elementArrayWithCode:(DescType)code
{
    SBElementArray *a = [[[SBElementArray alloc] init] autorelease];
    return a;
}
- (void)setTo:(id)value { [self _failed]; }

/* What the app's generated header declares, and the dictionary would
 * answer: a property, an element array or a command, each with object
 * arguments. They all answer nothing here. */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    if (sig)
        return sig;
    const char *name = sel_getName(sel);
    unsigned args = 0;
    for (const char *p = name; *p; p++)
        if (*p == ':')
            args++;
    char types[64] = "@@:";
    if (!strncmp(name, "set", 3) && args == 1)
        types[0] = 'v';
    for (unsigned i = 0; i < args && i < 40; i++)
        strcat(types, "@");
    return [NSMethodSignature signatureWithObjCTypes:types];
}
- (void)forwardInvocation:(NSInvocation *)inv
{
    [self _failed];
    NSMethodSignature *sig = [inv methodSignature];
    NSUInteger size = [sig methodReturnLength];
    if (size && *[sig methodReturnType] != 'v') {
        char zero[64] = {0};
        if (size <= sizeof zero)
            [inv setReturnValue:zero];
    }
}
@end

@implementation SBElementArray {
    NSMutableArray *_items;
}
- (instancetype)init
{
    if ((self = [super init]))
        _items = [[NSMutableArray alloc] init];
    return self;
}
- (instancetype)initWithCapacity:(NSUInteger)n { return [self init]; }
- (void)dealloc
{
    [_items release];
    [super dealloc];
}
- (NSUInteger)count { return [_items count]; }
- (id)objectAtIndex:(NSUInteger)i { return [_items objectAtIndex:i]; }
- (void)insertObject:(id)o atIndex:(NSUInteger)i { [_items insertObject:o atIndex:i]; }
- (void)removeObjectAtIndex:(NSUInteger)i { [_items removeObjectAtIndex:i]; }
- (void)addObject:(id)o { [_items addObject:o]; }
- (void)removeLastObject { [_items removeLastObject]; }
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)o { [_items replaceObjectAtIndex:i withObject:o]; }
- (id)objectWithName:(NSString *)name { return nil; }
- (id)objectWithID:(id)identifier { return nil; }
- (id)objectAtLocation:(id)location { return nil; }
- (NSArray *)arrayByApplyingSelector:(SEL)selector { return @[]; }
- (NSArray *)arrayByApplyingSelector:(SEL)selector withObject:(id)argument { return @[]; }
- (NSArray *)get { return @[]; }
- (NSError *)lastError { return not_handled(); }
@end

@implementation SBApplication {
    NSString *_bundleIdentifier;
    pid_t _pid;
    id<SBApplicationDelegate> _delegate;
    LSLaunchFlags _launchFlags;
    AESendMode _sendMode;
    long _timeout;
}
+ (instancetype)applicationWithBundleIdentifier:(NSString *)ident
{
    return [[[self alloc] initWithBundleIdentifier:ident] autorelease];
}
+ (instancetype)applicationWithURL:(NSURL *)url { return [[[self alloc] initWithURL:url] autorelease]; }
+ (instancetype)applicationWithProcessIdentifier:(pid_t)pid
{
    return [[[self alloc] initWithProcessIdentifier:pid] autorelease];
}
- (instancetype)_initKnown:(NSString *)ident pid:(pid_t)pid
{
    if ((self = [super init])) {
        _bundleIdentifier = [ident copy];
        _pid = pid;
        _timeout = 7200; /* a Mac's default, in ticks */
        [self _setApplication:self];
    }
    return self;
}
- (instancetype)initWithBundleIdentifier:(NSString *)ident
{
    if (![ident length] || ![[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:ident]) {
        [self release];
        return nil;
    }
    return [self _initKnown:ident pid:0];
}
- (instancetype)initWithURL:(NSURL *)url
{
    NSBundle *b = [url isFileURL] ? [NSBundle bundleWithURL:url] : nil;
    if (!b) {
        [self release];
        return nil;
    }
    return [self _initKnown:[b bundleIdentifier] pid:0];
}
- (instancetype)initWithProcessIdentifier:(pid_t)pid
{
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!app) {
        [self release];
        return nil;
    }
    return [self _initKnown:[app bundleIdentifier] pid:pid];
}
- (void)dealloc
{
    [_bundleIdentifier release];
    [_delegate release];
    [super dealloc];
}
- (Class)classForScriptingClass:(NSString *)className { return Nil; }
- (BOOL)isRunning
{
    if (_pid)
        return [NSRunningApplication runningApplicationWithProcessIdentifier:_pid] != nil;
    return _bundleIdentifier && [[NSRunningApplication runningApplicationsWithBundleIdentifier:_bundleIdentifier] count];
}
/* Bringing an app forward needs no Apple event; it is the one thing done. */
- (void)activate
{
    NSRunningApplication *app = _pid ? [NSRunningApplication runningApplicationWithProcessIdentifier:_pid]
                                     : [[NSRunningApplication runningApplicationsWithBundleIdentifier:_bundleIdentifier]
                                           firstObject];
    [app activateWithOptions:0];
}
- (id<SBApplicationDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<SBApplicationDelegate>)d
{
    [_delegate autorelease];
    _delegate = [d retain];
}
- (LSLaunchFlags)launchFlags { return _launchFlags; }
- (void)setLaunchFlags:(LSLaunchFlags)f { _launchFlags = f; }
- (AESendMode)sendMode { return _sendMode; }
- (void)setSendMode:(AESendMode)m { _sendMode = m; }
- (long)timeout { return _timeout; }
- (void)setTimeout:(long)t { _timeout = t; }
@end
