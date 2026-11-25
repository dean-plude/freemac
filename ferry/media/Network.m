/* SPDX-License-Identifier: GPL-3.0-or-later
 * Network.framework's path monitor for Ferry (freemac 1.232), from Apple's
 * public documentation. The path is read from Linux's /sys/class/net: the
 * computer is online (satisfied) when an interface other than loopback is
 * up and carrying; an interface with a wireless directory is Wi-Fi, one
 * named ww* or a cellular modem's is cellular, any other is wired. A
 * started monitor hands its queue the path at once and again whenever it
 * changes, looking every two seconds; cancelling it stops that and runs
 * the cancel handler. */
#import <Foundation/Foundation.h>
#include <Network/Network.h>

@interface FNWInterface : NSObject {
@public
    NSString *name;
    nw_interface_type_t type;
    uint32_t index;
}
@end
@implementation FNWInterface
- (void)dealloc { [name release]; [super dealloc]; }
@end

@interface FNWPath : NSObject {
@public
    nw_path_status_t status;
    NSArray *interfaces; /* the ones that are up, wired and Wi-Fi first */
}
@end
@implementation FNWPath
- (void)dealloc { [interfaces release]; [super dealloc]; }
- (NSString *)signature
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%d", status];
    for (FNWInterface *i in interfaces)
        [s appendFormat:@" %@:%d", i->name, i->type];
    return s;
}
@end

@interface FNWMonitor : NSObject {
@public
    dispatch_queue_t queue;
    nw_path_monitor_update_handler_t update;
    nw_path_monitor_cancel_handler_t cancel;
    BOOL started, cancelled, has_required;
    nw_interface_type_t required;
    NSString *last;
}
@end
@implementation FNWMonitor
- (void)dealloc
{
    if (queue)
        dispatch_release(queue);
    [update release];
    [cancel release];
    [last release];
    [super dealloc];
}
@end

static NSString *read_line(NSString *path)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static FNWPath *current_path(FNWMonitor *m)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = @"/sys/class/net";
    NSMutableArray *up = [NSMutableArray array];
    for (NSString *n in [[fm contentsOfDirectoryAtPath:root error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *dir = [root stringByAppendingPathComponent:n];
        if ([n isEqualToString:@"lo"])
            continue;
        NSString *state = read_line([dir stringByAppendingPathComponent:@"operstate"]);
        NSString *carrier = read_line([dir stringByAppendingPathComponent:@"carrier"]);
        /* virtual links report "unknown" while working; a carrier of 1 says so */
        if (!([state isEqualToString:@"up"] || ([state isEqualToString:@"unknown"] && [carrier isEqualToString:@"1"])))
            continue;
        FNWInterface *i = [[[FNWInterface alloc] init] autorelease];
        i->name = [n copy];
        i->index = (uint32_t)[read_line([dir stringByAppendingPathComponent:@"ifindex"]) intValue];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"wireless"]] ||
            [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"phy80211"]])
            i->type = nw_interface_type_wifi;
        else if ([n hasPrefix:@"ww"])
            i->type = nw_interface_type_cellular;
        else if ([n hasPrefix:@"tun"] || [n hasPrefix:@"wg"] || [n hasPrefix:@"docker"] || [n hasPrefix:@"veth"] ||
                 [n hasPrefix:@"br-"] || [n hasPrefix:@"virbr"])
            i->type = nw_interface_type_other;
        else
            i->type = nw_interface_type_wired;
        if (m && m->has_required && i->type != m->required)
            continue;
        [up addObject:i];
    }
    [up sortUsingComparator:^NSComparisonResult(FNWInterface *a, FNWInterface *b) {
        int ra = a->type == nw_interface_type_other ? 1 : 0, rb = b->type == nw_interface_type_other ? 1 : 0;
        return ra < rb ? NSOrderedAscending : ra > rb ? NSOrderedDescending : NSOrderedSame;
    }];
    FNWPath *p = [[[FNWPath alloc] init] autorelease];
    p->interfaces = [up copy];
    p->status = [up count] ? nw_path_status_satisfied : nw_path_status_unsatisfied;
    return p;
}

void *nw_retain(void *obj) { return [(id)obj retain]; }
void nw_release(void *obj) { [(id)obj release]; }

nw_path_monitor_t nw_path_monitor_create(void) { return (nw_path_monitor_t)[[FNWMonitor alloc] init]; }
nw_path_monitor_t nw_path_monitor_create_with_type(nw_interface_type_t type)
{
    FNWMonitor *m = [[FNWMonitor alloc] init];
    m->has_required = YES;
    m->required = type;
    return (nw_path_monitor_t)m;
}

#define MON(x) ((FNWMonitor *)(x))
void nw_path_monitor_set_queue(nw_path_monitor_t monitor, dispatch_queue_t queue)
{
    FNWMonitor *m = MON(monitor);
    if (queue)
        dispatch_retain(queue);
    if (m->queue)
        dispatch_release(m->queue);
    m->queue = queue;
}
void nw_path_monitor_set_update_handler(nw_path_monitor_t monitor, nw_path_monitor_update_handler_t handler)
{
    FNWMonitor *m = MON(monitor);
    [m->update release];
    m->update = [handler copy];
}
void nw_path_monitor_set_cancel_handler(nw_path_monitor_t monitor, nw_path_monitor_cancel_handler_t handler)
{
    FNWMonitor *m = MON(monitor);
    [m->cancel release];
    m->cancel = [handler copy];
}

/* runs on the monitor's queue */
static void look(FNWMonitor *m)
{
    if (m->cancelled)
        return;
    FNWPath *p = current_path(m);
    NSString *sig = [p signature];
    if (![sig isEqualToString:m->last]) {
        [m->last release];
        m->last = [sig copy];
        if (m->update)
            m->update((nw_path_t)p);
    }
    [m retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), m->queue, ^{
        look(m);
        [m release];
    });
}

void nw_path_monitor_start(nw_path_monitor_t monitor)
{
    FNWMonitor *m = MON(monitor);
    if (m->started || !m->queue)
        return;
    m->started = YES;
    [m retain];
    dispatch_async(m->queue, ^{
        look(m);
        [m release];
    });
}

void nw_path_monitor_cancel(nw_path_monitor_t monitor)
{
    FNWMonitor *m = MON(monitor);
    if (m->cancelled)
        return;
    m->cancelled = YES;
    nw_path_monitor_cancel_handler_t handler = [m->cancel retain];
    if (handler && m->queue)
        dispatch_async(m->queue, ^{
            handler();
            [handler release];
        });
    else if (handler) {
        handler();
        [handler release];
    }
}

#define PATH(x) ((FNWPath *)(x))
nw_path_status_t nw_path_get_status(nw_path_t path) { return path ? PATH(path)->status : nw_path_status_invalid; }
bool nw_path_is_expensive(nw_path_t path)
{
    for (FNWInterface *i in PATH(path)->interfaces)
        if (i->type == nw_interface_type_cellular)
            return true;
    return false;
}
bool nw_path_is_constrained(nw_path_t path) { return false; }
static bool has_file(NSString *path, NSString *word)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return s && (!word || [s rangeOfString:word].location != NSNotFound);
}
bool nw_path_has_ipv4(nw_path_t path) { return PATH(path)->status == nw_path_status_satisfied; }
bool nw_path_has_ipv6(nw_path_t path)
{
    if (PATH(path)->status != nw_path_status_satisfied)
        return false;
    NSString *s = [NSString stringWithContentsOfFile:@"/proc/net/if_inet6" encoding:NSUTF8StringEncoding error:NULL];
    for (NSString *line in [s componentsSeparatedByString:@"\n"])
        if ([line length] && ![line hasPrefix:@"fe80"] && ![line hasPrefix:@"00000000000000000000000000000001"])
            return true;
    return false;
}
bool nw_path_has_dns(nw_path_t path)
{
    return PATH(path)->status == nw_path_status_satisfied && has_file(@"/etc/resolv.conf", @"nameserver");
}
bool nw_path_uses_interface_type(nw_path_t path, nw_interface_type_t type)
{
    FNWInterface *first = [PATH(path)->interfaces firstObject];
    return first && first->type == type;
}
void nw_path_enumerate_interfaces(nw_path_t path, nw_path_enumerate_interfaces_block_t block)
{
    for (FNWInterface *i in PATH(path)->interfaces)
        if (!block((nw_interface_t)i))
            break;
}
bool nw_path_is_equal(nw_path_t a, nw_path_t b)
{
    return a == b || (a && b && [[PATH(a) signature] isEqualToString:[PATH(b) signature]]);
}

#define IFACE(x) ((FNWInterface *)(x))
nw_interface_type_t nw_interface_get_type(nw_interface_t i) { return IFACE(i)->type; }
const char *nw_interface_get_name(nw_interface_t i) { return [IFACE(i)->name UTF8String]; }
uint32_t nw_interface_get_index(nw_interface_t i) { return IFACE(i)->index; }
