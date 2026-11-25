/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's IOSurface (freemac 1.235, Ferry 0.59.0): image buffers that
 * Core Video, OpenGL and Core Animation share, written from Apple's public
 * IOSurface reference.
 *
 * A surface is page-aligned memory of the program's own, laid out as its
 * properties ask (one plane, or several each with its own rows), with the
 * values a program sets on it and a use count. Its ID and its "Mach port"
 * find it again within the program; there is no kernel object behind
 * either, so a surface can't be passed to another program as on a Mac.
 * Locking only counts the seed, as the memory is never moved. An
 * IOSurfaceRef is an object of the class IOSurface, so CFRetain and
 * CFRelease work on it. Built without ARC. */
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PLANES 4

const CFStringRef kIOSurfaceAllocSize = (CFStringRef)@"IOSurfaceAllocSize";
const CFStringRef kIOSurfaceWidth = (CFStringRef)@"IOSurfaceWidth";
const CFStringRef kIOSurfaceHeight = (CFStringRef)@"IOSurfaceHeight";
const CFStringRef kIOSurfaceBytesPerRow = (CFStringRef)@"IOSurfaceBytesPerRow";
const CFStringRef kIOSurfaceBytesPerElement = (CFStringRef)@"IOSurfaceBytesPerElement";
const CFStringRef kIOSurfaceElementWidth = (CFStringRef)@"IOSurfaceElementWidth";
const CFStringRef kIOSurfaceElementHeight = (CFStringRef)@"IOSurfaceElementHeight";
const CFStringRef kIOSurfaceOffset = (CFStringRef)@"IOSurfaceOffset";
const CFStringRef kIOSurfacePlaneInfo = (CFStringRef)@"IOSurfacePlaneInfo";
const CFStringRef kIOSurfacePlaneWidth = (CFStringRef)@"IOSurfacePlaneWidth";
const CFStringRef kIOSurfacePlaneHeight = (CFStringRef)@"IOSurfacePlaneHeight";
const CFStringRef kIOSurfacePlaneBytesPerRow = (CFStringRef)@"IOSurfacePlaneBytesPerRow";
const CFStringRef kIOSurfacePlaneOffset = (CFStringRef)@"IOSurfacePlaneOffset";
const CFStringRef kIOSurfacePlaneSize = (CFStringRef)@"IOSurfacePlaneSize";
const CFStringRef kIOSurfacePlaneBase = (CFStringRef)@"IOSurfacePlaneBase";
const CFStringRef kIOSurfacePlaneBitsPerElement = (CFStringRef)@"IOSurfacePlaneBitsPerElement";
const CFStringRef kIOSurfacePlaneBytesPerElement = (CFStringRef)@"IOSurfacePlaneBytesPerElement";
const CFStringRef kIOSurfacePlaneElementWidth = (CFStringRef)@"IOSurfacePlaneElementWidth";
const CFStringRef kIOSurfacePlaneElementHeight = (CFStringRef)@"IOSurfacePlaneElementHeight";
const CFStringRef kIOSurfaceCacheMode = (CFStringRef)@"IOSurfaceCacheMode";
const CFStringRef kIOSurfaceIsGlobal = (CFStringRef)@"IOSurfaceIsGlobal";
const CFStringRef kIOSurfacePixelFormat = (CFStringRef)@"IOSurfacePixelFormat";
const CFStringRef kIOSurfacePixelSizeCastingAllowed = (CFStringRef)@"IOSurfacePixelSizeCastingAllowed";
const CFStringRef kIOSurfacePlaneComponentBitDepths = (CFStringRef)@"IOSurfacePlaneComponentBitDepths";
const CFStringRef kIOSurfacePlaneComponentBitOffsets = (CFStringRef)@"IOSurfacePlaneComponentBitOffsets";
const CFStringRef kIOSurfaceName = (CFStringRef)@"IOSurfaceName";

IOSurfacePropertyKey IOSurfacePropertyKeyAllocSize = @"IOSurfaceAllocSize";
IOSurfacePropertyKey IOSurfacePropertyKeyWidth = @"IOSurfaceWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyHeight = @"IOSurfaceHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerRow = @"IOSurfaceBytesPerRow";
IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerElement = @"IOSurfaceBytesPerElement";
IOSurfacePropertyKey IOSurfacePropertyKeyElementWidth = @"IOSurfaceElementWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyElementHeight = @"IOSurfaceElementHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyOffset = @"IOSurfaceOffset";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneInfo = @"IOSurfacePlaneInfo";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneWidth = @"IOSurfacePlaneWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneHeight = @"IOSurfacePlaneHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerRow = @"IOSurfacePlaneBytesPerRow";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneOffset = @"IOSurfacePlaneOffset";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneSize = @"IOSurfacePlaneSize";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBase = @"IOSurfacePlaneBase";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerElement = @"IOSurfacePlaneBytesPerElement";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementWidth = @"IOSurfacePlaneElementWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementHeight = @"IOSurfacePlaneElementHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyCacheMode = @"IOSurfaceCacheMode";
IOSurfacePropertyKey IOSurfacePropertyKeyPixelFormat = @"IOSurfacePixelFormat";
IOSurfacePropertyKey IOSurfacePropertyKeyPixelSizeCastingAllowed = @"IOSurfacePixelSizeCastingAllowed";
IOSurfacePropertyKey IOSurfacePropertyKeyName = @"IOSurfaceName";

struct plane {
    size_t width, height, bytesPerRow, bytesPerElement, elementWidth, elementHeight, offset, size;
};

@interface IOSurface () {
  @public
    IOSurfaceID _id;
    OSType _format;
    size_t _width, _height, _bytesPerRow, _bytesPerElement, _elementWidth, _elementHeight, _offset;
    size_t _allocSize, _planeCount;
    struct plane _planes[MAX_PLANES];
    unsigned char *_memory;
    uint32_t _seed;
    int32_t _useCount;
    int32_t _locks;
    BOOL _castingAllowed;
    uint32_t _purgeable;
    NSMutableDictionary *_values;
    pthread_mutex_t _mutex;
}
@end

/* The surfaces alive now, by ID (not retained: a surface leaves when it goes). */
static pthread_mutex_t table_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct entry {
    IOSurfaceID id;
    IOSurface *surface;
} *table;
static size_t table_count, table_size;
static IOSurfaceID last_id;

/* called with table_mutex held */
static IOSurface *table_find(IOSurfaceID sid)
{
    for (size_t i = 0; i < table_count; i++)
        if (table[i].id == sid)
            return table[i].surface;
    return nil;
}
static int table_add(IOSurfaceID sid, IOSurface *s)
{
    if (table_count == table_size) {
        size_t n = table_size ? table_size * 2 : 32;
        struct entry *t = realloc(table, n * sizeof *t);
        if (!t)
            return 0;
        table = t;
        table_size = n;
    }
    table[table_count].id = sid;
    table[table_count++].surface = s;
    return 1;
}
static void table_remove(IOSurfaceID sid)
{
    for (size_t i = 0; i < table_count; i++)
        if (table[i].id == sid) {
            table[i] = table[--table_count];
            return;
        }
}

/* the "Mach port" of a surface: its ID with a mark, which only this
 * program's IOSurfaceLookupFromMachPort understands */
#define PORT_MARK 0x51000000u

static size_t number(NSDictionary *d, id key, size_t otherwise)
{
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(unsignedLongLongValue)] ? (size_t)[v unsignedLongLongValue] : otherwise;
}

static size_t align_up(size_t v, size_t a) { return a ? (v + a - 1) / a * a : v; }

@implementation IOSurface

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithProperties:(NSDictionary *)p
{
    if (!(self = [super init]))
        return nil;
    pthread_mutex_init(&_mutex, NULL);
    _values = [[NSMutableDictionary alloc] init];
    _width = number(p, @"IOSurfaceWidth", 0);
    _height = number(p, @"IOSurfaceHeight", 0);
    _format = (OSType)number(p, @"IOSurfacePixelFormat", 0);
    _bytesPerElement = number(p, @"IOSurfaceBytesPerElement", 0);
    _elementWidth = number(p, @"IOSurfaceElementWidth", 1);
    _elementHeight = number(p, @"IOSurfaceElementHeight", 1);
    _offset = number(p, @"IOSurfaceOffset", 0);
    _castingAllowed = [[p objectForKey:@"IOSurfacePixelSizeCastingAllowed"] boolValue];
    if (!_elementWidth)
        _elementWidth = 1;
    if (!_elementHeight)
        _elementHeight = 1;
    NSArray *planes = [p objectForKey:@"IOSurfacePlaneInfo"];
    size_t end = 0;
    if ([planes isKindOfClass:[NSArray class]] && planes.count) {
        size_t next = _offset;
        for (NSDictionary *d in planes) {
            if (_planeCount == MAX_PLANES || ![d isKindOfClass:[NSDictionary class]])
                break;
            struct plane *q = &_planes[_planeCount++];
            q->width = number(d, @"IOSurfacePlaneWidth", _width);
            q->height = number(d, @"IOSurfacePlaneHeight", _height);
            q->bytesPerElement = number(d, @"IOSurfacePlaneBytesPerElement", 1);
            q->elementWidth = number(d, @"IOSurfacePlaneElementWidth", 1);
            q->elementHeight = number(d, @"IOSurfacePlaneElementHeight", 1);
            if (!q->elementWidth)
                q->elementWidth = 1;
            if (!q->elementHeight)
                q->elementHeight = 1;
            q->bytesPerRow = number(d, @"IOSurfacePlaneBytesPerRow",
                                    align_up((q->width + q->elementWidth - 1) / q->elementWidth * q->bytesPerElement, 16));
            q->offset = number(d, @"IOSurfacePlaneOffset", align_up(next, 16));
            q->size = number(d, @"IOSurfacePlaneSize",
                             q->bytesPerRow * ((q->height + q->elementHeight - 1) / q->elementHeight));
            next = q->offset + q->size;
            if (next > end)
                end = next;
        }
        if (!_bytesPerRow)
            _bytesPerRow = number(p, @"IOSurfaceBytesPerRow", 0);
    } else {
        if (!_bytesPerElement)
            _bytesPerElement = 4;
        _bytesPerRow = number(p, @"IOSurfaceBytesPerRow",
                              align_up((_width + _elementWidth - 1) / _elementWidth * _bytesPerElement, 16));
        end = _offset + _bytesPerRow * ((_height + _elementHeight - 1) / _elementHeight);
    }
    _allocSize = number(p, @"IOSurfaceAllocSize", 0);
    if (_allocSize < end)
        _allocSize = end;
    if (!_allocSize || _width > 65536 || _height > 65536) {
        [self release];
        return nil;
    }
    _allocSize = align_up(_allocSize, 4096);
    if (posix_memalign((void **)&_memory, 4096, _allocSize)) {
        _memory = NULL;
        [self release];
        return nil;
    }
    memset(_memory, 0, _allocSize);
    id name = [p objectForKey:@"IOSurfaceName"];
    if (name)
        [_values setObject:name forKey:@"IOSurfaceName"];
    pthread_mutex_lock(&table_mutex);
    do
        _id = ++last_id;
    while (!_id || table_find(_id));
    int added = table_add(_id, self);
    pthread_mutex_unlock(&table_mutex);
    if (!added) {
        _id = 0;
        [self release];
        return nil;
    }
    return self;
}

- (oneway void)release
{
    /* the last release and a lookup by ID race: take the table's lock so a
     * lookup never retains a surface on its way out */
    pthread_mutex_lock(&table_mutex);
    if ([self retainCount] == 1 && _id) {
        table_remove(_id);
        _id = 0;
    }
    pthread_mutex_unlock(&table_mutex);
    [super release];
}

- (void)dealloc
{
    free(_memory);
    [_values release];
    pthread_mutex_destroy(&_mutex);
    [super dealloc];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self release];
    IOSurfaceID sid = (IOSurfaceID)[coder decodeInt64ForKey:@"IOSurfaceID"];
    return (IOSurface *)IOSurfaceLookup(sid);
}

- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeInt64:_id forKey:@"IOSurfaceID"]; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<IOSurface %p id %u %zux%zu '%c%c%c%c' %zu planes>", self, _id, _width,
                                      _height, (int)(_format >> 24 & 0xff), (int)(_format >> 16 & 0xff),
                                      (int)(_format >> 8 & 0xff), (int)(_format & 0xff), _planeCount];
}

- (kern_return_t)lockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed
{
    __atomic_add_fetch(&_locks, 1, __ATOMIC_ACQ_REL);
    if (seed)
        *seed = __atomic_load_n(&_seed, __ATOMIC_ACQUIRE);
    return kIOReturnSuccess;
}

- (kern_return_t)unlockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed
{
    if (__atomic_sub_fetch(&_locks, 1, __ATOMIC_ACQ_REL) < 0) {
        __atomic_add_fetch(&_locks, 1, __ATOMIC_ACQ_REL);
        return kIOReturnError;
    }
    uint32_t s = !(options & kIOSurfaceLockReadOnly) ? __atomic_add_fetch(&_seed, 1, __ATOMIC_ACQ_REL)
                                                     : __atomic_load_n(&_seed, __ATOMIC_ACQUIRE);
    if (seed)
        *seed = s;
    return kIOReturnSuccess;
}

- (NSInteger)allocationSize { return (NSInteger)_allocSize; }
- (NSInteger)width { return (NSInteger)_width; }
- (NSInteger)height { return (NSInteger)_height; }
- (void *)baseAddress { return _memory + (_planeCount ? 0 : _offset); }
- (OSType)pixelFormat { return _format; }
- (NSInteger)bytesPerRow { return (NSInteger)_bytesPerRow; }
- (NSInteger)bytesPerElement { return (NSInteger)_bytesPerElement; }
- (NSInteger)elementWidth { return (NSInteger)_elementWidth; }
- (NSInteger)elementHeight { return (NSInteger)_elementHeight; }
- (uint32_t)seed { return __atomic_load_n(&_seed, __ATOMIC_ACQUIRE); }
- (NSUInteger)planeCount { return _planeCount; }
- (NSInteger)widthOfPlaneAtIndex:(NSUInteger)i { return i < _planeCount ? (NSInteger)_planes[i].width : 0; }
- (NSInteger)heightOfPlaneAtIndex:(NSUInteger)i { return i < _planeCount ? (NSInteger)_planes[i].height : 0; }
- (NSInteger)bytesPerRowOfPlaneAtIndex:(NSUInteger)i { return i < _planeCount ? (NSInteger)_planes[i].bytesPerRow : 0; }
- (NSInteger)bytesPerElementOfPlaneAtIndex:(NSUInteger)i
{
    return i < _planeCount ? (NSInteger)_planes[i].bytesPerElement : 0;
}
- (NSInteger)elementWidthOfPlaneAtIndex:(NSUInteger)i { return i < _planeCount ? (NSInteger)_planes[i].elementWidth : 0; }
- (NSInteger)elementHeightOfPlaneAtIndex:(NSUInteger)i
{
    return i < _planeCount ? (NSInteger)_planes[i].elementHeight : 0;
}
- (void *)baseAddressOfPlaneAtIndex:(NSUInteger)i { return i < _planeCount ? _memory + _planes[i].offset : NULL; }

- (void)setAttachment:(id)o forKey:(NSString *)key
{
    if (!key)
        return;
    pthread_mutex_lock(&_mutex);
    if (o)
        [_values setObject:o forKey:key];
    else
        [_values removeObjectForKey:key];
    pthread_mutex_unlock(&_mutex);
}
- (id)attachmentForKey:(NSString *)key
{
    pthread_mutex_lock(&_mutex);
    id o = key ? [[[_values objectForKey:key] retain] autorelease] : nil;
    pthread_mutex_unlock(&_mutex);
    return o;
}
- (void)removeAttachmentForKey:(NSString *)key { [self setAttachment:nil forKey:key]; }
- (void)setAllAttachments:(NSDictionary *)dict
{
    pthread_mutex_lock(&_mutex);
    [_values addEntriesFromDictionary:dict];
    pthread_mutex_unlock(&_mutex);
}
- (NSDictionary *)allAttachments
{
    pthread_mutex_lock(&_mutex);
    NSDictionary *d = [[_values copy] autorelease];
    pthread_mutex_unlock(&_mutex);
    return d;
}
- (void)removeAllAttachments
{
    pthread_mutex_lock(&_mutex);
    [_values removeAllObjects];
    pthread_mutex_unlock(&_mutex);
}

- (BOOL)isInUse { return __atomic_load_n(&_useCount, __ATOMIC_ACQUIRE) > 0; }
- (void)incrementUseCount { __atomic_add_fetch(&_useCount, 1, __ATOMIC_ACQ_REL); }
- (void)decrementUseCount { __atomic_sub_fetch(&_useCount, 1, __ATOMIC_ACQ_REL); }
- (int32_t)localUseCount { return __atomic_load_n(&_useCount, __ATOMIC_ACQUIRE); }
- (BOOL)allowsPixelSizeCasting { return _castingAllowed; }

- (kern_return_t)setPurgeable:(IOSurfacePurgeabilityState)state oldState:(IOSurfacePurgeabilityState *)old
{
    /* the memory is never given back, so a surface made volatile keeps its contents */
    if (old)
        *old = _purgeable;
    if (state != kIOSurfacePurgeableKeepCurrent)
        _purgeable = state == kIOSurfacePurgeableEmpty ? kIOSurfacePurgeableVolatile : state;
    return KERN_SUCCESS;
}

@end

/* ---- the C calls ------------------------------------------------------------------ */

#define S(ref) ((IOSurface *)(ref))

CFTypeID IOSurfaceGetTypeID(void) { return (CFTypeID)[IOSurface class]; }

IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties)
{
    if (!properties)
        return NULL;
    return (IOSurfaceRef)[[IOSurface alloc] initWithProperties:(NSDictionary *)properties];
}

IOSurfaceRef IOSurfaceLookup(IOSurfaceID csid)
{
    IOSurface *s = nil;
    pthread_mutex_lock(&table_mutex);
    if (csid)
        s = [table_find(csid) retain];
    pthread_mutex_unlock(&table_mutex);
    return (IOSurfaceRef)s;
}

IOSurfaceID IOSurfaceGetID(IOSurfaceRef b) { return b ? S(b)->_id : 0; }
IOReturn IOSurfaceLock(IOSurfaceRef b, IOSurfaceLockOptions o, uint32_t *seed)
{
    return b ? [S(b) lockWithOptions:o seed:seed] : kIOReturnBadArgument;
}
IOReturn IOSurfaceUnlock(IOSurfaceRef b, IOSurfaceLockOptions o, uint32_t *seed)
{
    return b ? [S(b) unlockWithOptions:o seed:seed] : kIOReturnBadArgument;
}
size_t IOSurfaceGetAllocSize(IOSurfaceRef b) { return b ? S(b)->_allocSize : 0; }
size_t IOSurfaceGetWidth(IOSurfaceRef b) { return b ? S(b)->_width : 0; }
size_t IOSurfaceGetHeight(IOSurfaceRef b) { return b ? S(b)->_height : 0; }
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef b) { return b ? S(b)->_bytesPerElement : 0; }
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef b) { return b ? S(b)->_bytesPerRow : 0; }
void *IOSurfaceGetBaseAddress(IOSurfaceRef b) { return b ? [S(b) baseAddress] : NULL; }
size_t IOSurfaceGetElementWidth(IOSurfaceRef b) { return b ? S(b)->_elementWidth : 0; }
size_t IOSurfaceGetElementHeight(IOSurfaceRef b) { return b ? S(b)->_elementHeight : 0; }
OSType IOSurfaceGetPixelFormat(IOSurfaceRef b) { return b ? S(b)->_format : 0; }
uint32_t IOSurfaceGetSeed(IOSurfaceRef b) { return b ? [S(b) seed] : 0; }
size_t IOSurfaceGetPlaneCount(IOSurfaceRef b) { return b ? S(b)->_planeCount : 0; }

/* A surface without planes answers for plane 0 with its own geometry, as
 * Apple's reference describes. */
static const struct plane *plane_of(IOSurfaceRef b, size_t i, struct plane *whole)
{
    if (!b)
        return NULL;
    IOSurface *s = S(b);
    if (i < s->_planeCount)
        return &s->_planes[i];
    if (s->_planeCount || i)
        return NULL;
    whole->width = s->_width;
    whole->height = s->_height;
    whole->bytesPerRow = s->_bytesPerRow;
    whole->bytesPerElement = s->_bytesPerElement;
    whole->elementWidth = s->_elementWidth;
    whole->elementHeight = s->_elementHeight;
    whole->offset = s->_offset;
    whole->size = s->_allocSize - s->_offset;
    return whole;
}

#define PLANE_GETTER(fn, field)                                                                                   \
    size_t fn(IOSurfaceRef b, size_t i)                                                                           \
    {                                                                                                             \
        struct plane whole;                                                                                       \
        const struct plane *q = plane_of(b, i, &whole);                                                           \
        return q ? q->field : 0;                                                                                  \
    }
PLANE_GETTER(IOSurfaceGetWidthOfPlane, width)
PLANE_GETTER(IOSurfaceGetHeightOfPlane, height)
PLANE_GETTER(IOSurfaceGetBytesPerElementOfPlane, bytesPerElement)
PLANE_GETTER(IOSurfaceGetBytesPerRowOfPlane, bytesPerRow)
PLANE_GETTER(IOSurfaceGetElementWidthOfPlane, elementWidth)
PLANE_GETTER(IOSurfaceGetElementHeightOfPlane, elementHeight)

void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef b, size_t i)
{
    struct plane whole;
    const struct plane *q = plane_of(b, i, &whole);
    return q ? S(b)->_memory + q->offset : NULL;
}

/* The components of the pixel formats Core Video makes, lowest bits first. */
struct components {
    int count;
    IOSurfaceComponentName name[4];
    uint8_t depth[4], offset[4];
};
static int components_of(IOSurfaceRef b, size_t plane, struct components *c)
{
    memset(c, 0, sizeof *c);
    if (!b)
        return 0;
    enum { A = 1, R, G, B, Y, CR, CB };
    static const struct {
        OSType format;
        int plane;
        struct components c;
    } formats[] = {
        {'BGRA', 0, {4, {B, G, R, A}, {8, 8, 8, 8}, {0, 8, 16, 24}}},
        {'RGBA', 0, {4, {R, G, B, A}, {8, 8, 8, 8}, {0, 8, 16, 24}}},
        {0x20, 0, {4, {A, R, G, B}, {8, 8, 8, 8}, {0, 8, 16, 24}}},
        {'l10r', 0, {4, {B, G, R, A}, {10, 10, 10, 2}, {0, 10, 20, 30}}},
        {'L008', 0, {1, {Y}, {8}, {0}}},
        {'420v', 0, {1, {Y}, {8}, {0}}},
        {'420v', 1, {2, {CB, CR}, {8, 8}, {0, 8}}},
        {'420f', 0, {1, {Y}, {8}, {0}}},
        {'420f', 1, {2, {CB, CR}, {8, 8}, {0, 8}}},
        {'y420', 0, {1, {Y}, {8}, {0}}},
        {'y420', 1, {1, {CB}, {8}, {0}}},
        {'y420', 2, {1, {CR}, {8}, {0}}},
        {'f420', 0, {1, {Y}, {8}, {0}}},
        {'f420', 1, {1, {CB}, {8}, {0}}},
        {'f420', 2, {1, {CR}, {8}, {0}}},
    };
    OSType f = S(b)->_format;
    for (size_t i = 0; i < sizeof formats / sizeof *formats; i++)
        if (formats[i].format == f && (size_t)formats[i].plane == plane) {
            *c = formats[i].c;
            return c->count;
        }
    return 0;
}

size_t IOSurfaceGetNumberOfComponentsOfPlane(IOSurfaceRef b, size_t plane)
{
    struct components c;
    return (size_t)components_of(b, plane, &c);
}
IOSurfaceComponentName IOSurfaceGetNameOfComponentOfPlane(IOSurfaceRef b, size_t plane, size_t i)
{
    struct components c;
    return i < (size_t)components_of(b, plane, &c) ? c.name[i] : kIOSurfaceComponentNameUnknown;
}
uint8_t IOSurfaceGetBitDepthOfComponentOfPlane(IOSurfaceRef b, size_t plane, size_t i)
{
    struct components c;
    return i < (size_t)components_of(b, plane, &c) ? c.depth[i] : 0;
}
uint8_t IOSurfaceGetBitOffsetOfComponentOfPlane(IOSurfaceRef b, size_t plane, size_t i)
{
    struct components c;
    return i < (size_t)components_of(b, plane, &c) ? c.offset[i] : 0;
}

void IOSurfaceSetValue(IOSurfaceRef b, CFStringRef key, CFTypeRef value)
{
    if (b)
        [S(b) setAttachment:(id)value forKey:(NSString *)key];
}
CFTypeRef IOSurfaceCopyValue(IOSurfaceRef b, CFStringRef key)
{
    return b ? (CFTypeRef)[[S(b) attachmentForKey:(NSString *)key] retain] : NULL;
}
void IOSurfaceRemoveValue(IOSurfaceRef b, CFStringRef key)
{
    if (b)
        [S(b) removeAttachmentForKey:(NSString *)key];
}
void IOSurfaceSetValues(IOSurfaceRef b, CFDictionaryRef d)
{
    if (b && d)
        [S(b) setAllAttachments:(NSDictionary *)d];
}
CFDictionaryRef IOSurfaceCopyAllValues(IOSurfaceRef b)
{
    return b ? (CFDictionaryRef)[[S(b) allAttachments] retain] : NULL;
}
void IOSurfaceRemoveAllValues(IOSurfaceRef b)
{
    if (b)
        [S(b) removeAllAttachments];
}

mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef b) { return b && S(b)->_id < 0x01000000u ? PORT_MARK | S(b)->_id : 0; }
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port)
{
    return (port & 0xff000000u) == PORT_MARK ? IOSurfaceLookup(port & 0x00ffffffu) : NULL;
}

size_t IOSurfaceGetPropertyMaximum(CFStringRef property)
{
    NSString *p = (NSString *)property;
    if ([p isEqual:@"IOSurfaceWidth"] || [p isEqual:@"IOSurfaceHeight"] || [p isEqual:@"IOSurfacePlaneWidth"] ||
        [p isEqual:@"IOSurfacePlaneHeight"])
        return 65536;
    if ([p isEqual:@"IOSurfaceBytesPerRow"] || [p isEqual:@"IOSurfacePlaneBytesPerRow"])
        return 65536 * 16;
    return SIZE_MAX;
}
size_t IOSurfaceGetPropertyAlignment(CFStringRef property)
{
    NSString *p = (NSString *)property;
    if ([p isEqual:@"IOSurfaceBytesPerRow"] || [p isEqual:@"IOSurfacePlaneBytesPerRow"] ||
        [p isEqual:@"IOSurfaceOffset"] || [p isEqual:@"IOSurfacePlaneOffset"])
        return 16;
    if ([p isEqual:@"IOSurfaceAllocSize"])
        return 4096;
    return 1;
}
size_t IOSurfaceAlignProperty(CFStringRef property, size_t value)
{
    return align_up(value, IOSurfaceGetPropertyAlignment(property));
}

void IOSurfaceIncrementUseCount(IOSurfaceRef b)
{
    if (b)
        [S(b) incrementUseCount];
}
void IOSurfaceDecrementUseCount(IOSurfaceRef b)
{
    if (b)
        [S(b) decrementUseCount];
}
int32_t IOSurfaceGetUseCount(IOSurfaceRef b) { return b ? [S(b) localUseCount] : 0; }
Boolean IOSurfaceIsInUse(IOSurfaceRef b) { return b && [S(b) isInUse]; }
Boolean IOSurfaceAllowsPixelSizeCasting(IOSurfaceRef b) { return b && S(b)->_castingAllowed; }
kern_return_t IOSurfaceSetPurgeable(IOSurfaceRef b, uint32_t state, uint32_t *old)
{
    if (!b)
        return kIOReturnBadArgument;
    IOSurfacePurgeabilityState o = 0;
    kern_return_t r = [S(b) setPurgeable:state oldState:&o];
    if (old)
        *old = o;
    return r;
}
