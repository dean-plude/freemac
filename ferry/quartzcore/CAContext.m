/* SPDX-License-Identifier: GPL-3.0-or-later
 * Showing one program's layer in another's window (freemac, Godot work):
 * CAContext and CALayerHost (sdk/include/QuartzCore/CAContext.h). Apple
 * keeps these out of its public SDK; what is here is the behaviour that
 * open-source Mac programs rely on (the Godot 4.5 editor shows its running
 * game in its Game tab this way): a context gives a layer tree an ID that
 * any program can name, and a layer host with that ID shows the tree as
 * its own sublayer, placed by the tree's anchor point and position.
 *
 * On freemac a context publishes its layer as a picture in shared memory,
 * /dev/shm/ferry-cacontext-<id>, each time the layer changes and each time
 * a Metal drawable is presented to it (from the presenting thread, since a
 * program that shows its layers elsewhere need not run its main run loop,
 * as Godot's embedded game doesn't). The file holds two pictures, written
 * in turn, so that a reader always has a whole one. A host reads the
 * newest picture sixty times a second on the main run loop and shows it;
 * when the program that published it is gone, the host goes blank and
 * removes the file. */
#import "QInternal.h"
#import <QuartzCore/CAContext.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const kCAContextCIFilterBehavior = @"filter";
NSString *const kCAContextDisplayable = @"displayable";
NSString *const kCAContextIgnoresHitTest = @"ignoresHitTest";

/* ---- the shared picture ----------------------------------------------------------------- */

#define SHARED_MAGIC 0x58414346u   /* "FCAX" */
#define SHARED_HEADER 4096

typedef struct {
    uint32_t width, height;           /* pixels, BGRA premultiplied, top row first */
    uint32_t opaque, pad;
    double scale;                     /* the layer's contentsScale */
    double bw, bh, ax, ay, px, py;    /* its bounds size, anchor point and position */
} SharedFrame;

typedef struct {
    uint32_t magic, version;
    int32_t pid;
    uint32_t serial;                  /* pictures written so far */
    uint32_t slot;                    /* the one that holds the newest */
    uint32_t pad;
    uint64_t slotBytes;
    SharedFrame frames[2];
} SharedHeader;

static void shared_path(CAContextID cid, char *buf, size_t n)
{
    snprintf(buf, n, "/dev/shm/ferry-cacontext-%u", (unsigned)cid);
}

/* ---- CAContext ------------------------------------------------------------------------------ */

static pthread_mutex_t contexts_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray *live_contexts;   /* not retained: NSValues of the contexts */
static uint32_t next_context;

@interface CAContext ()
- (void)_ferryPublishImage:(CGImageRef)img;
- (void)_ferryLayerTreeChanged;
@end

static void remove_files_at_exit(void)
{
    pthread_mutex_lock(&contexts_lock);
    for (NSValue *v in live_contexts) {
        char path[96];
        shared_path([(CAContext *)[v pointerValue] contextId], path, sizeof path);
        unlink(path);
    }
    pthread_mutex_unlock(&contexts_lock);
}

@implementation CAContext {
    CAContextID _id;
    CALayer *_layer;
    NSDictionary *_options;
    BOOL _valid;
    pthread_mutex_t _lock;
    int _fd;
    uint8_t *_map;
    size_t _mapSize;
    BOOL _publishing;
}

+ (instancetype)contextWithCGSConnection:(uint32_t)connection options:(NSDictionary *)options
{
    (void)connection;
    return [[[self alloc] _ferryInitWithOptions:options] autorelease];
}
+ (instancetype)remoteContextWithOptions:(NSDictionary *)options
{
    return [[[self alloc] _ferryInitWithOptions:options] autorelease];
}
+ (instancetype)localContextWithOptions:(NSDictionary *)options
{
    return [[[self alloc] _ferryInitWithOptions:options] autorelease];
}
+ (NSArray<CAContext *> *)allContexts
{
    NSMutableArray *out = [NSMutableArray array];
    pthread_mutex_lock(&contexts_lock);
    for (NSValue *v in live_contexts)
        [out addObject:(CAContext *)[v pointerValue]];
    pthread_mutex_unlock(&contexts_lock);
    return out;
}

- (instancetype)_ferryInitWithOptions:(NSDictionary *)options
{
    if (!(self = [super init]))
        return nil;
    pthread_mutex_init(&_lock, NULL);
    _options = [options copy];
    _fd = -1;
    _valid = YES;
    pthread_mutex_lock(&contexts_lock);
    if (!live_contexts) {
        live_contexts = [NSMutableArray new];
        atexit(remove_files_at_exit);
    }
    /* an ID no other program's context has: the process and a count */
    _id = ((uint32_t)getpid() & 0x3fffff) << 8 | (++next_context & 0xff);
    if (!_id)
        _id = 1;
    [live_contexts addObject:[NSValue valueWithPointer:self]];
    pthread_mutex_unlock(&contexts_lock);
    return self;
}

- (void)_ferryCloseShared
{
    if (_map)
        munmap(_map, _mapSize);
    _map = NULL;
    _mapSize = 0;
    if (_fd >= 0) {
        close(_fd);
        char path[96];
        shared_path(_id, path, sizeof path);
        unlink(path);
    }
    _fd = -1;
}

- (void)invalidate
{
    [self setLayer:nil];
    pthread_mutex_lock(&_lock);
    _valid = NO;
    [self _ferryCloseShared];
    pthread_mutex_unlock(&_lock);
}

- (void)dealloc
{
    pthread_mutex_lock(&contexts_lock);
    for (NSUInteger i = 0; i < [live_contexts count]; i++)
        if ([live_contexts[i] pointerValue] == self) {
            [live_contexts removeObjectAtIndex:i];
            break;
        }
    pthread_mutex_unlock(&contexts_lock);
    if (_layer && [_layer _ferryHost] == self)
        FerryCALayerSetHost(_layer, nil);
    [_layer release];
    [_options release];
    [self _ferryCloseShared];
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}

- (CAContextID)contextId { return _id; }
- (NSDictionary *)options { return _options; }
- (BOOL)valid { return _valid; }
- (CALayer *)layer { return _layer; }

- (void)setLayer:(CALayer *)layer
{
    if (layer == _layer)
        return;
    if (_layer && [_layer _ferryHost] == self)
        FerryCALayerSetHost(_layer, nil);
    [layer retain];
    [_layer release];
    _layer = layer;
    if (layer) {
        /* the layer's changes reach this context as a window's would */
        FerryCALayerSetHost(layer, self);
        [self _ferryLayerTreeChanged];
    }
}

/* Room for two pictures of `bytes` each, the file made or grown as needed. */
- (BOOL)_ferryRoomFor:(size_t)bytes
{
    if (_fd < 0) {
        char path[96];
        shared_path(_id, path, sizeof path);
        _fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (_fd < 0) {
            QWarnOnce("sharing a layer with another program (no /dev/shm)");
            return NO;
        }
    }
    size_t need = SHARED_HEADER + 2 * bytes;
    if (_map && _mapSize >= need)
        return YES;
    uint64_t slot = _map ? ((SharedHeader *)_map)->slotBytes : 0;
    uint32_t serial = _map ? ((SharedHeader *)_map)->serial : 0;
    if (_map)
        munmap(_map, _mapSize);
    _map = NULL;
    uint64_t newSlot = bytes + bytes / 4;   /* some room to grow */
    if (newSlot < slot)
        newSlot = slot;
    size_t size = SHARED_HEADER + 2 * (size_t)newSlot;
    if (ftruncate(_fd, (off_t)size) != 0)
        return NO;
    void *m = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, _fd, 0);
    if (m == MAP_FAILED)
        return NO;
    _map = m;
    _mapSize = size;
    SharedHeader *h = (SharedHeader *)_map;
    h->magic = SHARED_MAGIC;
    h->version = 1;
    h->pid = (int32_t)getpid();
    h->serial = serial;
    __atomic_store_n(&h->slotBytes, newSlot, __ATOMIC_RELEASE);
    return YES;
}

/* Writes the layer's picture: `img` when a drawable gave it, else the
 * layer tree drawn. */
- (void)_ferryPublishImage:(CGImageRef)img
{
    CALayer *layer = _layer;
    if (!layer || !_valid)
        return;
    pthread_mutex_lock(&_lock);
    if (_publishing) {   /* drawing the tree changed it again */
        pthread_mutex_unlock(&_lock);
        return;
    }
    _publishing = YES;
    NSDictionary *v = [layer _ferryValues];
    CGRect b = QRect(v, @"bounds");
    double scale = QNum(v, @"contentsScale");
    if (scale <= 0)
        scale = 1;
    CGPoint ap = QPoint(v, @"anchorPoint"), pos = QPoint(v, @"position");
    size_t w = (size_t)ceil(b.size.width * scale), hgt = (size_t)ceil(b.size.height * scale);
    if (img && (!w || !hgt)) {
        w = CGImageGetWidth(img);
        hgt = CGImageGetHeight(img);
    }
    if (w && hgt && w <= 16384 && hgt <= 16384 && [self _ferryRoomFor:w * hgt * 4]) {
        SharedHeader *h = (SharedHeader *)_map;
        uint32_t s = (h->serial + 1) & 1;
        uint8_t *pixels = _map + SHARED_HEADER + s * h->slotBytes;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(pixels, w, hgt, 8, w * 4, cs,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(cs);
        if (c) {
            CGContextClearRect(c, CGRectMake(0, 0, w, hgt));
            if (img) {
                CGContextDrawImage(c, CGRectMake(0, 0, w, hgt), img);
            } else {
                CGContextScaleCTM(c, scale, scale);
                CGContextTranslateCTM(c, -b.origin.x, -b.origin.y);
                FerryCALayerRender(layer, c, NO, NO, nil);
            }
            CGContextRelease(c);
            SharedFrame *f = &h->frames[s];
            f->width = (uint32_t)w;
            f->height = (uint32_t)hgt;
            f->opaque = QBool(v, @"opaque");
            f->scale = scale;
            f->bw = b.size.width ? b.size.width : w / scale;
            f->bh = b.size.height ? b.size.height : hgt / scale;
            f->ax = ap.x;
            f->ay = ap.y;
            f->px = pos.x;
            f->py = pos.y;
            __atomic_store_n(&h->slot, s, __ATOMIC_RELEASE);
            __atomic_add_fetch(&h->serial, 1, __ATOMIC_RELEASE);
        }
    }
    _publishing = NO;
    pthread_mutex_unlock(&_lock);
}

/* The layer tree changed: its picture again. */
- (void)_ferryLayerTreeChanged { [self _ferryPublishImage:NULL]; }
@end

/* Whether the layer is in a context's tree: a Metal layer there shows a
 * presented drawable at once, from the thread that presented it, since the
 * program may never run its main run loop (CAMetalLayer.m) */
BOOL FerryCALayerInContext(CALayer *layer)
{
    while ([layer superlayer])
        layer = [layer superlayer];
    return [[layer _ferryHost] isKindOfClass:[CAContext class]];
}

/* ---- CALayerHost ------------------------------------------------------------------------ */

@implementation CALayerHost {
    CAContextID _contextId;
    dispatch_source_t _timer;
    int _fd;
    uint8_t *_map;
    size_t _mapSize;
    uint32_t _seen;
    CALayer *_remote;   /* the context's layer as last published */
}

- (instancetype)init
{
    if ((self = [super init]))
        _fd = -1;
    return self;
}

- (void)_ferryUnmap
{
    if (_map)
        munmap(_map, _mapSize);
    _map = NULL;
    _mapSize = 0;
    if (_fd >= 0)
        close(_fd);
    _fd = -1;
    _seen = 0;
}

- (void)_ferryStopReading
{
    if (_timer) {
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
        _timer = NULL;
    }
    [self _ferryUnmap];
}

- (void)dealloc
{
    [self _ferryStopReading];
    [_remote release];
    [super dealloc];
}

- (CAContextID)contextId { return _contextId; }

- (void)setContextId:(CAContextID)cid
{
    if (cid == _contextId)
        return;
    [self _ferryStopReading];
    _contextId = cid;
    [self _ferryShowRemote:NULL frame:NULL];
    if (!cid)
        return;
    /* read on the main queue, never keeping the host alive */
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 60, NSEC_PER_SEC / 240);
    __block CALayerHost *me = self;   /* (not retained: the host owns the timer) */
    dispatch_source_set_event_handler(_timer, ^{
      [me _ferryReadShared];
    });
    dispatch_resume(_timer);
}

/* The published layer, shown as this layer's one sublayer of its own */
- (void)_ferryShowRemote:(CGImageRef)img frame:(const SharedFrame *)f
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!img) {
        [_remote removeFromSuperlayer];
        [_remote release];
        _remote = nil;
    } else {
        if (!_remote) {
            _remote = [[CALayer alloc] init];
            [self addSublayer:_remote];
        }
        _remote.bounds = CGRectMake(0, 0, f->bw, f->bh);
        _remote.anchorPoint = CGPointMake(f->ax, f->ay);
        _remote.position = CGPointMake(f->px, f->py);
        _remote.contentsScale = f->scale;
        _remote.opaque = f->opaque != 0;
        _remote.contents = (id)img;
    }
    [CATransaction commit];
}

static void pixels_done(void *info, const void *data, size_t size)
{
    (void)info;
    (void)size;
    free((void *)data);
}

- (void)_ferryReadShared
{
    if (_fd < 0) {
        char path[96];
        shared_path(_contextId, path, sizeof path);
        _fd = open(path, O_RDONLY);
        if (_fd < 0)
            return;   /* not published yet */
    }
    struct stat st;
    if (fstat(_fd, &st) != 0)
        return;
    if (st.st_nlink == 0) {   /* the context invalidated: blank */
        [self _ferryUnmap];
        [self _ferryShowRemote:NULL frame:NULL];
        return;
    }
    if ((size_t)st.st_size < SHARED_HEADER)
        return;
    if (!_map || (size_t)st.st_size != _mapSize) {
        if (_map)
            munmap(_map, _mapSize);
        _map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_SHARED, _fd, 0);
        if (_map == MAP_FAILED) {
            _map = NULL;
            _mapSize = 0;
            return;
        }
        _mapSize = (size_t)st.st_size;
    }
    const SharedHeader *h = (const SharedHeader *)_map;
    if (h->magic != SHARED_MAGIC)
        return;
    uint32_t serial = __atomic_load_n(&h->serial, __ATOMIC_ACQUIRE);
    if (serial == _seen) {
        /* the program that published it gone: blank, and its file removed */
        if (h->pid > 0 && kill(h->pid, 0) != 0 && errno == ESRCH) {
            char path[96];
            shared_path(_contextId, path, sizeof path);
            unlink(path);
            [self _ferryUnmap];
            [self _ferryShowRemote:NULL frame:NULL];
        }
        return;
    }
    for (int tries = 0; tries < 3; tries++) {
        uint32_t s = __atomic_load_n(&h->slot, __ATOMIC_ACQUIRE) & 1;
        uint64_t slotBytes = __atomic_load_n(&h->slotBytes, __ATOMIC_ACQUIRE);
        SharedFrame f = h->frames[s];
        size_t bytes = (size_t)f.width * f.height * 4;
        if (!bytes || bytes > slotBytes || SHARED_HEADER + (s + 1) * slotBytes > _mapSize)
            return;   /* the file is growing: next time */
        uint8_t *copy = malloc(bytes);
        if (!copy)
            return;
        memcpy(copy, _map + SHARED_HEADER + s * slotBytes, bytes);
        uint32_t after = __atomic_load_n(&h->serial, __ATOMIC_ACQUIRE);
        if (after - serial >= 2) {   /* written over while copied */
            free(copy);
            serial = after;
            continue;
        }
        CGDataProviderRef p = CGDataProviderCreateWithData(NULL, copy, bytes, pixels_done);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGImageRef img = CGImageCreate(f.width, f.height, 8, 32, (size_t)f.width * 4, cs,
                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, p, NULL, false,
                                       kCGRenderingIntentDefault);
        CGColorSpaceRelease(cs);
        CGDataProviderRelease(p);
        if (img) {
            [self _ferryShowRemote:img frame:&f];
            CGImageRelease(img);
        }
        _seen = serial;
        return;
    }
}
@end
