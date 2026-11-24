/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSDistributedNotificationCenter, written from
 * Apple's public documentation (freemac 1.213, Ferry 0.39.0). Where a Mac
 * passes distributed notifications through a daemon, Ferry's programs pass
 * them on the D-Bus session bus, with this system's GIO (reached through
 * ferry_bus_symbol, src/host.c): a post is a broadcast signal, Posted on
 * the interface org.freemac.Ferry.DistributedNotifications at the path
 * /org/freemac/Ferry/DistributedNotifications, carrying the name, the
 * object string, the user info as a binary property list and whether to
 * deliver it at once. Every Ferry program with an observer listens for
 * that signal, the poster included, and its observers are told on the main
 * thread as the main run loop turns, through a GLib main context of the
 * center's own. With no session bus (no address, and no socket in
 * XDG_RUNTIME_DIR, so D-Bus is never started for us) or when the bus can't
 * be reached, the center quietly works within the program: what is posted
 * is delivered to its own observers, also on the main thread as the run
 * loop turns. While the center is suspended each observer is treated as
 * its suspension behaviour says (dropped, coalesced to one, held, or
 * delivered anyway), and a post to deliver at once is delivered to all,
 * after what was held. Our own code; no Apple code was used. */
#import "FInternal.h"
#include <Foundation/NSDistributedNotificationCenter.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

void *ferry_bus_symbol(const char *name); /* src/host.c */

NSDistributedNotificationCenterType const NSLocalNotificationCenterType = @"NSLocalNotificationCenterType";

#define PATH "/org/freemac/Ferry/DistributedNotifications"
#define IFACE "org.freemac.Ferry.DistributedNotifications"
#define MEMBER "Posted"
#define SIGNATURE "(ssbayb)"

/* ---- GIO, looked up the first time it's needed -------------------------------------- */

typedef struct _GMainContext GMainContext;
typedef struct _GDBusConnection GDBusConnection;
typedef struct _GVariant GVariant;
typedef struct {
    uint32_t domain;
    int code;
    char *message;
} GError;
typedef void (*GSignalCallback)(GDBusConnection *connection, const char *sender, const char *path,
                                const char *iface, const char *member, GVariant *parameters, void *data);

static struct {
    GDBusConnection *(*bus_get_sync)(int type, void *cancellable, GError **error);
    unsigned (*subscribe)(GDBusConnection *c, const char *sender, const char *iface, const char *member,
                          const char *path, const char *arg0, int flags, GSignalCallback callback, void *data,
                          void (*free_data)(void *));
    int (*emit)(GDBusConnection *c, const char *destination, const char *path, const char *iface,
                const char *member, GVariant *parameters, GError **error);
    int (*flush)(GDBusConnection *c, void *cancellable, GError **error);
    GVariant *(*new_string)(const char *s);
    GVariant *(*new_boolean)(int b);
    GVariant *(*new_fixed_array)(const void *type, const void *elements, size_t n, size_t size);
    GVariant *(*new_tuple)(GVariant *const *children, size_t n);
    GVariant *(*child)(GVariant *v, size_t i);
    const char *(*get_string)(GVariant *v, size_t *length);
    int (*get_boolean)(GVariant *v);
    const void *(*get_fixed_array)(GVariant *v, size_t *n, size_t size);
    const char *(*type_string)(GVariant *v);
    void (*unref)(GVariant *v);
    GMainContext *(*context_new)(void);
    void (*push)(GMainContext *c);
    void (*pop)(GMainContext *c);
    int (*acquire)(GMainContext *c);
    int (*prepare)(GMainContext *c, int *priority);
    int (*query)(GMainContext *c, int priority, int *timeout, struct pollfd *fds, int n);
    int (*check)(GMainContext *c, int priority, struct pollfd *fds, int n);
    void (*dispatch)(GMainContext *c);
    void (*error_free)(GError *e);
} G;

static BOOL load_gio(void)
{
#define LOOK(field, name)                                                                                       \
    if (!(*(void **)&G.field = ferry_bus_symbol(name)))                                                         \
        return NO;
    LOOK(bus_get_sync, "g_bus_get_sync")
    LOOK(subscribe, "g_dbus_connection_signal_subscribe")
    LOOK(emit, "g_dbus_connection_emit_signal")
    LOOK(flush, "g_dbus_connection_flush_sync")
    LOOK(new_string, "g_variant_new_string")
    LOOK(new_boolean, "g_variant_new_boolean")
    LOOK(new_fixed_array, "g_variant_new_fixed_array")
    LOOK(new_tuple, "g_variant_new_tuple")
    LOOK(child, "g_variant_get_child_value")
    LOOK(get_string, "g_variant_get_string")
    LOOK(get_boolean, "g_variant_get_boolean")
    LOOK(get_fixed_array, "g_variant_get_fixed_array")
    LOOK(type_string, "g_variant_get_type_string")
    LOOK(unref, "g_variant_unref")
    LOOK(context_new, "g_main_context_new")
    LOOK(push, "g_main_context_push_thread_default")
    LOOK(pop, "g_main_context_pop_thread_default")
    LOOK(acquire, "g_main_context_acquire")
    LOOK(prepare, "g_main_context_prepare")
    LOOK(query, "g_main_context_query")
    LOOK(check, "g_main_context_check")
    LOOK(dispatch, "g_main_context_dispatch")
    LOOK(error_free, "g_error_free")
#undef LOOK
    return YES;
}

/* Whether a session bus is there to connect to, without having D-Bus
 * start one: an address given, or the usual socket in XDG_RUNTIME_DIR. */
static BOOL bus_present(void)
{
    const char *address = getenv("DBUS_SESSION_BUS_ADDRESS");
    if (address && *address)
        return YES;
    const char *dir = getenv("XDG_RUNTIME_DIR");
    if (!dir || !*dir)
        return NO;
    char path[4096];
    snprintf(path, sizeof path, "%s/bus", dir);
    struct stat st;
    return stat(path, &st) == 0 && (st.st_mode & 0170000) == 0140000;
}

static GDBusConnection *bus;           /* NULL: within the program only */
static GMainContext *context;
static unsigned subscription;
static BOOL acquired;
static int priority;
static NSDistributedNotificationCenter *shared;

static void connect_bus(void)
{
    if (!bus_present() || !load_gio())
        return;
    GError *error = NULL;
    bus = G.bus_get_sync(2 /* G_BUS_TYPE_SESSION */, NULL, &error);
    if (!bus && error)
        G.error_free(error);
}

/* ---- observations ----------------------------------------------------------------------- */

@interface FDistObservation : NSObject {
@public
    id observer;            /* not retained, as on a Mac; the observation itself for a block */
    SEL selector;
    NSString *name, *object;
    void (^block)(NSNotification *);
    NSOperationQueue *queue;
    NSNotificationSuspensionBehavior behaviour;
    BOOL removed;
}
@end
@implementation FDistObservation
- (void)dealloc
{
    [name release];
    [object release];
    [block release];
    [queue release];
    [super dealloc];
}
@end

@interface NSDistributedNotificationCenter (FerryPrivate)
- (void)_arrived:(NSNotification *)note immediately:(BOOL)immediately;
@end

/* ---- the bus's side ---------------------------------------------------------------------- */

static void on_signal(GDBusConnection *c, const char *sender, const char *path, const char *iface, const char *member,
                      GVariant *params, void *data)
{
    if (strcmp(G.type_string(params), SIGNATURE))
        return;
    @autoreleasepool {
        GVariant *v[5];
        for (int i = 0; i < 5; i++)
            v[i] = G.child(params, (size_t)i);
        NSString *name = [NSString stringWithUTF8String:G.get_string(v[0], NULL)];
        NSString *object = G.get_boolean(v[2]) ? [NSString stringWithUTF8String:G.get_string(v[1], NULL)] : nil;
        size_t n = 0;
        const void *bytes = G.get_fixed_array(v[3], &n, 1);
        NSDictionary *info = nil;
        if (n) {
            id plist = [NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:bytes length:n]
                                                                 options:NSPropertyListImmutable
                                                                  format:NULL
                                                                   error:NULL];
            if ([plist isKindOfClass:[NSDictionary class]])
                info = plist;
        }
        BOOL immediately = G.get_boolean(v[4]) != 0;
        for (int i = 0; i < 5; i++)
            G.unref(v[i]);
        if (name)
            [shared _arrived:[NSNotification notificationWithName:name object:object userInfo:info]
                 immediately:immediately];
    }
}

static BOOL poller_active(void *ctx) { return subscription != 0; }

static int poller_prepare(void *ctx, int *timeout_ms, struct pollfd *fds, int max)
{
    if (!acquired)
        acquired = G.acquire(context) != 0;
    int timeout = -1;
    G.prepare(context, &priority);
    int n = G.query(context, priority, &timeout, fds, max);
    if (n > max)
        n = max;
    if (timeout >= 0 && timeout < *timeout_ms)
        *timeout_ms = timeout;
    return n;
}

static BOOL poller_dispatch(void *ctx, struct pollfd *fds, int count)
{
    if (!G.check(context, priority, fds, count))
        return NO;
    G.dispatch(context);
    return YES;
}

/* Listens for posts, once the center has an observer. */
static void subscribe(void)
{
    if (!bus || subscription)
        return;
    if (!context) {
        context = G.context_new();
        FRunLoopAddPoller(poller_prepare, poller_dispatch, poller_active, NULL);
    }
    G.push(context);
    subscription = G.subscribe(bus, NULL, IFACE, MEMBER, PATH, NULL, 0, on_signal, NULL, NULL);
    G.pop(context);
}

static BOOL emit(NSString *name, NSString *object, NSData *info, BOOL immediately)
{
    GVariant *v[5] = {
        G.new_string([name UTF8String]), G.new_string(object ? [object UTF8String] : ""), G.new_boolean(object != nil),
        G.new_fixed_array("y", [info bytes] ?: "", [info length], 1), G.new_boolean(immediately),
    };
    GError *error = NULL;
    BOOL sent = G.emit(bus, NULL, PATH, IFACE, MEMBER, G.new_tuple(v, 5), &error) != 0;
    if (error) {
        G.error_free(error);
        error = NULL;
    }
    if (sent && !G.flush(bus, NULL, &error) && error)
        G.error_free(error);
    return sent;
}

/* ---- the center ---------------------------------------------------------------------- */

@implementation NSDistributedNotificationCenter {
    NSMutableArray *_observing;     /* FDistObservations */
    NSMutableArray *_held;          /* [observation, notification] pairs, while suspended */
    BOOL _suspended;
    NSLock *_lock;
}

+ (NSDistributedNotificationCenter *)defaultCenter
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      shared = [[NSDistributedNotificationCenter alloc] init];
      connect_bus();
    });
    return shared;
}
+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSDistributedNotificationCenterType)type
{
    return [type isEqual:NSLocalNotificationCenterType] ? [self defaultCenter] : nil;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _observing = [[NSMutableArray alloc] init];
        _held = [[NSMutableArray alloc] init];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)suspended { return _suspended; }
- (void)setSuspended:(BOOL)flag
{
    if (flag == _suspended)
        return;
    _suspended = flag;
    if (!flag)
        [self _deliverHeld];
}

static void check_object(id object)
{
    if (object && ![object isKindOfClass:[NSString class]])
        FRaise(NSInvalidArgumentException, @"NSDistributedNotificationCenter: the object must be a string, not %@",
               [object class]);
}

- (void)_add:(FDistObservation *)o
{
    [_lock lock];
    [_observing addObject:o];
    [_lock unlock];
    if (bus)
        subscribe();
}

- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(NSString *)object
    suspensionBehavior:(NSNotificationSuspensionBehavior)behaviour
{
    check_object(object);
    FDistObservation *o = [[FDistObservation alloc] init];
    o->observer = observer;
    o->selector = selector;
    o->name = [name copy];
    o->object = [object copy];
    o->behaviour = behaviour;
    [self _add:o];
    [o release];
}
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(id)object
{
    [self addObserver:observer selector:selector name:name object:object
        suspensionBehavior:NSNotificationSuspensionBehaviorCoalesce];
}
- (id)addObserverForName:(NSNotificationName)name object:(id)object queue:(NSOperationQueue *)queue
              usingBlock:(void (^)(NSNotification *))block
{
    check_object(object);
    FDistObservation *o = [[FDistObservation alloc] init];
    o->observer = o;
    o->name = [name copy];
    o->object = [object copy];
    o->block = [block copy];
    o->queue = [queue retain];
    o->behaviour = NSNotificationSuspensionBehaviorCoalesce;
    [self _add:o];
    return [o autorelease];
}

- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object
{
    NSMutableArray *gone = [[NSMutableArray alloc] init];
    [_lock lock];
    for (NSUInteger i = [_observing count]; i-- > 0;) {
        FDistObservation *o = _observing[i];
        if (o->observer != observer || (name && ![o->name isEqual:name]) || (object && ![o->object isEqual:object]))
            continue;
        o->removed = YES;
        [gone addObject:o];
        [_observing removeObjectAtIndex:i];
    }
    for (NSUInteger i = [_held count]; i-- > 0;)
        if (((FDistObservation *)_held[i][0])->removed)
            [_held removeObjectAtIndex:i];
    [_lock unlock];
    [gone release];
}
- (void)removeObserver:(id)observer { [self removeObserver:observer name:nil object:nil]; }

/* ---- posting -------------------------------------------------------------------------- */

- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)info
                     options:(NSDistributedNotificationOptions)options
{
    check_object(object);
    if (!name)
        FRaise(NSInvalidArgumentException, @"NSDistributedNotificationCenter: a notification needs a name");
    BOOL immediately = (options & NSDistributedNotificationDeliverImmediately) != 0;
    NSData *data = nil;
    if ([info count])
        data = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListBinaryFormat_v1_0
                                                         options:0
                                                           error:NULL];
    if (bus && emit(name, object, data, immediately))
        return;
    /* within the program: its own observers, as the main run loop turns */
    NSDictionary *kept = data ? [NSPropertyListSerialization propertyListWithData:data
                                                                          options:NSPropertyListImmutable
                                                                           format:NULL
                                                                            error:NULL]
                              : nil;
    NSNotification *note = [NSNotification notificationWithName:name object:object userInfo:kept];
    [self performSelectorOnMainThread:@selector(_arrivedHere:) withObject:@[ note, @(immediately) ]
                        waitUntilDone:NO];
}
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)info
          deliverImmediately:(BOOL)immediately
{
    [self postNotificationName:name object:object userInfo:info
                       options:immediately ? NSDistributedNotificationDeliverImmediately : 0];
}
- (void)postNotification:(NSNotification *)note
{
    [self postNotificationName:[note name] object:[note object] userInfo:[note userInfo] options:0];
}
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object
{
    [self postNotificationName:name object:object userInfo:nil options:0];
}
- (void)postNotificationName:(NSNotificationName)name object:(NSString *)object userInfo:(NSDictionary *)info
{
    [self postNotificationName:name object:object userInfo:info options:0];
}

/* ---- delivering ----------------------------------------------------------------------- */

static void tell(FDistObservation *o, NSNotification *note)
{
    if (o->removed)
        return;
    if (o->block) {
        if (o->queue) {
            void (^b)(NSNotification *) = [[o->block retain] autorelease];
            [o->queue addOperationWithBlock:^{
              b(note);
            }];
        } else {
            o->block(note);
        }
    } else {
        ((void (*)(id, SEL, id))objc_msgSend)(o->observer, o->selector, note);
    }
}

- (void)_arrivedHere:(NSArray *)pair { [self _arrived:pair[0] immediately:[pair[1] boolValue]]; }

- (void)_deliverHeld
{
    [_lock lock];
    NSArray *held = [[_held copy] autorelease];
    [_held removeAllObjects];
    [_lock unlock];
    for (NSArray *pair in held)
        tell(pair[0], pair[1]);
}

- (void)_arrived:(NSNotification *)note immediately:(BOOL)immediately
{
    if (immediately && _suspended)
        [self _deliverHeld];
    [_lock lock];
    NSArray *now = [[_observing copy] autorelease];
    [_lock unlock];
    NSString *name = [note name], *object = [note object];
    for (FDistObservation *o in now) {
        if (o->removed || (o->name && ![o->name isEqual:name]) || (o->object && ![o->object isEqual:object]))
            continue;
        if (!_suspended || immediately || o->behaviour == NSNotificationSuspensionBehaviorDeliverImmediately) {
            tell(o, note);
            continue;
        }
        if (o->behaviour == NSNotificationSuspensionBehaviorDrop)
            continue;
        [_lock lock];
        BOOL merged = NO;
        if (o->behaviour == NSNotificationSuspensionBehaviorCoalesce)
            for (NSUInteger i = 0; i < [_held count]; i++) {
                NSArray *pair = _held[i];
                NSNotification *was = pair[1];
                if (pair[0] == o && [[was name] isEqual:name] &&
                    ([was object] == object || [[was object] isEqual:object])) {
                    _held[i] = @[ o, note ];
                    merged = YES;
                    break;
                }
            }
        if (!merged)
            [_held addObject:@[ o, note ]];
        [_lock unlock];
    }
}
@end
